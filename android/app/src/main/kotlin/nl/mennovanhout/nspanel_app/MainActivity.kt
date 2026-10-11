package nl.mennovanhout.nspanel_app

import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var touchGuard: WakeTouchGuard
    private var displayEvents: EventChannel.EventSink? = null
    private var saverVisible = false
    private var nativeIdleTimeout: Int? = null
    private var displayLock: PowerManager.WakeLock? = null
    private val awakeHold = DisplayAwakeHold(
        acquire = {
            // NSPanel firmware can drop WindowManager's KEEP_SCREEN_ON lock
            // after waking. Hold our own while the app owns the awake display.
            // No ACQUIRE_CAUSES_WAKEUP: sleep events must remain authoritative.
            @Suppress("DEPRECATION")
            val lock = power.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ON_AFTER_RELEASE, "nspanel:display")
            lock.setReferenceCounted(false)
            lock.acquire()
            displayLock = lock
        },
        release = {
            displayLock?.let { if (it.isHeld) it.release() }
            displayLock = null
        })
    private fun updateAwakeHold() {
        awakeHold.update(nativeIdleTimeout != null, foreground, power.isInteractive)
    }
    private fun restoreSystemTimeout() {
        val timeout = nativeIdleTimeout ?: return
        if (Settings.System.canWrite(this) && Settings.System.getInt(contentResolver,
                Settings.System.SCREEN_OFF_TIMEOUT, -1) != timeout) {
            Settings.System.putInt(contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, timeout)
        }
    }
    private var foreground = true
    private var fingers = 0
    private var lastTouch: MotionEvent? = null
    private var receiverRegistered = false
    private val displayHandler = Handler(Looper.getMainLooper())
    private val timeoutObserver = object : ContentObserver(displayHandler) {
        override fun onChange(selfChange: Boolean) {
            if (foreground) restoreSystemTimeout()
        }
    }
    private var lifecycleGeneration = 0
    private val power get() = getSystemService(Context.POWER_SERVICE) as PowerManager

    private fun emitDisplay(kind: String) {
        displayEvents?.success(mapOf("kind" to kind, "interactive" to power.isInteractive,
            "foreground" to foreground, "fingers" to fingers))
    }

    private fun cancelTouch() {
        lastTouch?.let { previous ->
            val cancel = MotionEvent.obtain(previous)
            cancel.action = MotionEvent.ACTION_CANCEL
            super.dispatchTouchEvent(cancel)
            cancel.recycle()
        }
        fingers = 0
        lastTouch?.recycle()
        lastTouch = null
    }

    private fun syncScreen() {
        updateAwakeHold()
        if (!::touchGuard.isInitialized) return
        val on = power.isInteractive
        val wentOff = touchGuard.interactive && !on
        if (touchGuard.screen(on)) cancelTouch()
        else if (wentOff) {
            fingers = 0
            lastTouch?.recycle()
            lastTouch = null
        }
    }

    private val displayReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            syncScreen()
            if (intent.action == "android.system.gestures.touchDown") {
                if (!power.isInteractive && foreground) emitDisplay("wake")
            } else {
                emitDisplay("screen")
            }
        }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        syncScreen()
        val start = event.actionMasked == MotionEvent.ACTION_DOWN
        val finish = event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL
        val wasSaver = saverVisible
        val allow = touchGuard.allow(start, finish, event.downTime, wasSaver)
        fingers = when (event.actionMasked) {
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> 0
            MotionEvent.ACTION_POINTER_UP -> event.pointerCount - 1
            else -> event.pointerCount
        }
        // All physical fingers inhibit idle, including a swallowed wake gesture.
        // MOVE need not cross the channel: DOWN/UP already bracket its lifetime.
        if (event.actionMasked != MotionEvent.ACTION_MOVE) emitDisplay("touch")
        if (start && (!power.isInteractive || wasSaver)) {
            if (power.isInteractive) touchGuard.protect()
            emitDisplay("wake")
        }
        if (!allow) return true
        lastTouch?.recycle()
        lastTouch = if (finish) null else MotionEvent.obtain(event)
        return super.dispatchTouchEvent(event)
    }

    override fun onResume() {
        super.onResume()
        lifecycleGeneration++
        foreground = true
        restoreSystemTimeout()
        syncScreen()
        emitDisplay("lifecycle")
    }

    override fun onPause() {
        super.onPause()
        val generation = ++lifecycleGeneration
        // SCREEN_OFF and onPause may arrive in either order. Sleeping our own
        // activity must keep the sensor alive; another foreground app must not.
        displayHandler.postDelayed({
            if (generation == lifecycleGeneration && power.isInteractive) {
                restoreSystemTimeout()
                foreground = false
                updateAwakeHold()
                if (::touchGuard.isInitialized && touchGuard.cancel()) cancelTouch()
                fingers = 0
                emitDisplay("lifecycle")
            }
        }, 200)
    }

    private var proximityListener: SensorEventListener? = null
    private var lightListener: SensorEventListener? = null

    // Touch feedback: a SoundPool click is the only thing on Android that
    // plays within a frame of the touch (MediaPlayer/just_audio take a
    // hundred milliseconds to start, which reads as lag, not feedback).
    private var pool: SoundPool? = null
    private var tickId = 0
    private var tickReady = false

    // Held while the screensaver has put the display to sleep, so the SoC
    // keeps feeding the proximity sensor and the MQTT socket in the dark.
    private var cpuLock: PowerManager.WakeLock? = null

    private fun loadTick() {
        if (pool != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val p = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attrs).build()
        p.setOnLoadCompleteListener { _, _, status -> tickReady = status == 0 }
        val key = io.flutter.FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/sounds/pop.wav")
        assets.openFd(key).use { fd -> tickId = p.load(fd, 1) }
        pool = p
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        touchGuard = WakeTouchGuard({ SystemClock.uptimeMillis() }, power.isInteractive)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction("android.system.gestures.touchDown")
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(displayReceiver, filter, Context.RECEIVER_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(displayReceiver, filter)
        receiverRegistered = true
        contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.SCREEN_OFF_TIMEOUT), false, timeoutObserver)
        // A wall panel that goes to sleep is a wall. No plugin needed for one flag.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /// A sensor as an event stream, registered only while Dart listens.
    private fun sensorStream(sensors: SensorManager, sensor: Sensor?, keep: (SensorEventListener?) -> Unit) =
        object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                if (sensor == null) {
                    events.error("no_sensor", "This device has no such sensor", null)
                    return
                }
                val l = object : SensorEventListener {
                    override fun onSensorChanged(e: SensorEvent) { events.success(e.values[0].toDouble()) }
                    override fun onAccuracyChanged(s: Sensor?, a: Int) {}
                }
                keep(l)
                sensors.registerListener(l, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            }
            override fun onCancel(arguments: Any?) {
                keep(null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        loadTick() // ahead of the first touch, which would otherwise be silent
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "nl.mennovanhout.nspanel/displayEvents").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    displayEvents = events
                    emitDisplay("snapshot")
                }
                override fun onCancel(arguments: Any?) { displayEvents = null }
            })
        MethodChannel(messenger, "nl.mennovanhout.nspanel/displayControl").setMethodCallHandler { call, result ->
            when (call.method) {
                "idleTimeout" -> {
                    nativeIdleTimeout = (call.arguments as? Number)?.toInt()?.coerceIn(10000, 86400000)
                    restoreSystemTimeout()
                    updateAwakeHold()
                    result.success(null)
                }
                "saver" -> {
                    val wasSaver = saverVisible
                    saverVisible = call.arguments == true
                    if (wasSaver && !saverVisible && ::touchGuard.isInitialized && power.isInteractive) {
                        touchGuard.protect()
                    }
                    if (saverVisible && ::touchGuard.isInitialized && touchGuard.cancel()) {
                        cancelTouch()
                        emitDisplay("snapshot")
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val proximity = sensors.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        val light = sensors.getDefaultSensor(Sensor.TYPE_LIGHT)
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // The NSPanel Pro's proximity sensor streams a graded value at ~10 Hz;
        // the light sensor reports lux. Both are on-change and cheap.
        EventChannel(messenger, "nl.mennovanhout.nspanel/proximity").setStreamHandler(
            sensorStream(sensors, proximity) { l ->
                proximityListener?.let { sensors.unregisterListener(it) }
                proximityListener = l
            })
        EventChannel(messenger, "nl.mennovanhout.nspanel/light").setStreamHandler(
            sensorStream(sensors, light) { l ->
                lightListener?.let { sensors.unregisterListener(it) }
                lightListener = l
            })

        MethodChannel(messenger, "nl.mennovanhout.nspanel/sensors").setMethodCallHandler { call, result ->
            when (call.method) {
                "proximityMaxRange" -> result.success(proximity?.maximumRange?.toDouble())
                // adb shell am start -n <this activity> --ez setup true : open the setup screen
                "wantsSetup" -> {
                    val wants = intent?.getBooleanExtra("setup", false) ?: false
                    intent?.removeExtra("setup")
                    result.success(wants)
                }
                "androidId" -> result.success(
                    Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
                "wifiRssi" -> {
                    val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    result.success(wifi.connectionInfo?.rssi)
                }
                "getBrightness" -> result.success(
                    Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, -1))
                "setBrightness" -> {
                    // WRITE_SETTINGS is a one-time grant on the panel:
                    //   adb shell appops set nl.mennovanhout.nspanel WRITE_SETTINGS allow
                    if (!Settings.System.canWrite(this)) { result.success(false); return@setMethodCallHandler }
                    val v = (call.arguments as Int).coerceIn(0, 255)
                    Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                    Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, v)
                    val lp = window.attributes
                    lp.screenBrightness = v / 255f
                    window.attributes = lp
                    result.success(true)
                }
                "hasVibrator" -> {
                    val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    result.success(v?.hasVibrator() == true)
                }
                // straight to the Vibrator, not View.performHapticFeedback, which
                // the system's "haptic feedback" toggle can silently turn off
                "vibrate" -> {
                    val ms = ((call.arguments as? Int) ?: 15).toLong().coerceIn(1, 200)
                    val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                    if (v == null || !v.hasVibrator()) { result.success(false); return@setMethodCallHandler }
                    if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
                    else @Suppress("DEPRECATION") v.vibrate(ms)
                    result.success(true)
                }
                "tick" -> {
                    loadTick()
                    val vol = ((call.arguments as? Double) ?: 0.5).toFloat().coerceIn(0f, 1f)
                    if (tickReady) pool?.play(tickId, vol, vol, 1, 0, 1f)
                    result.success(tickReady)
                }
                "isInteractive" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isInteractive)
                }
                // The one way an app turns a sleeping display back on without
                // system permissions: a bright wake lock flagged to cause the
                // wake-up. Deprecated since API 17, still what the framework
                // honours on 27, and this panel is 27.
                "wakeScreen" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    @Suppress("DEPRECATION")
                    val wl = pm.newWakeLock(
                        PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP
                            or PowerManager.ON_AFTER_RELEASE, "nspanel:wake")
                    wl.acquire(3000)
                    result.success(true)
                }
                "holdCpu" -> {
                    val on = call.arguments as? Boolean ?: false
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (on) {
                        if (cpuLock == null) {
                            cpuLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nspanel:dark")
                            cpuLock?.acquire()
                        }
                    } else {
                        cpuLock?.let { if (it.isHeld) it.release() }
                        cpuLock = null
                    }
                    result.success(true)
                }
                "getVolume" -> {
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (max > 0) cur * 100 / max else 0)
                }
                "setVolume" -> {
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val pct = (call.arguments as Int).coerceIn(0, 100)
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(pct * max / 100f), 0)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        awakeHold.update(false, false, false)
        lifecycleGeneration++
        displayHandler.removeCallbacksAndMessages(null)
        if (receiverRegistered) {
            unregisterReceiver(displayReceiver)
            contentResolver.unregisterContentObserver(timeoutObserver)
        }
        displayEvents = null
        lastTouch?.recycle()
        lastTouch = null
        pool?.release()
        pool = null
        cpuLock?.let { if (it.isHeld) it.release() }
        cpuLock = null
        val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        proximityListener?.let { sensors.unregisterListener(it) }
        lightListener?.let { sensors.unregisterListener(it) }
        super.onDestroy()
    }
}
