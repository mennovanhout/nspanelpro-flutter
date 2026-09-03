package nl.mennovanhout.nspanel_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var proximityListener: SensorEventListener? = null
    private var lightListener: SensorEventListener? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        val messenger = flutterEngine.dartExecutor.binaryMessenger
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
        val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        proximityListener?.let { sensors.unregisterListener(it) }
        lightListener?.let { sensors.unregisterListener(it) }
        super.onDestroy()
    }
}
