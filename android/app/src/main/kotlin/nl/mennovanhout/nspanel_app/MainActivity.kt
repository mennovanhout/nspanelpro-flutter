package nl.mennovanhout.nspanel_app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var proximityListener: SensorEventListener? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A wall panel that goes to sleep is a wall. No plugin needed for one flag.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val proximity = sensors.getDefaultSensor(Sensor.TYPE_PROXIMITY)

        // The NSPanel Pro's proximity sensor streams a graded value at ~10 Hz.
        // Registered only while Dart is listening - during the screensaver -
        // so it costs nothing while the dashboard is in use.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nl.mennovanhout.nspanel/proximity")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    if (proximity == null) {
                        events.error("no_sensor", "This device has no proximity sensor", null)
                        return
                    }
                    val l = object : SensorEventListener {
                        override fun onSensorChanged(e: SensorEvent) {
                            events.success(e.values[0].toDouble())
                        }
                        override fun onAccuracyChanged(s: Sensor?, a: Int) {}
                    }
                    proximityListener = l
                    sensors.registerListener(l, proximity, SensorManager.SENSOR_DELAY_NORMAL)
                }

                override fun onCancel(arguments: Any?) {
                    proximityListener?.let { sensors.unregisterListener(it) }
                    proximityListener = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nl.mennovanhout.nspanel/sensors")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "proximityMaxRange" -> result.success(proximity?.maximumRange?.toDouble())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        proximityListener?.let {
            (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(it)
        }
        super.onDestroy()
    }
}
