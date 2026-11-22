package com.resonance.app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity。
 *
 * 1) 继承 AudioServiceActivity（而不是 FlutterActivity）：音频后台服务与 Activity
 *    必须共用同一个 FlutterEngine，否则通知点开后会起第二个引擎/黑屏。
 * 2) 承担「用回响打开 .json」的入口：系统通过 ACTION_VIEW 把文件交进来，
 *    这里把内容读成文本推给 Dart（MethodChannel: resonance/open_file）。
 * 3) 车载蓝牙状态：MethodChannel resonance/car_lyrics + EventChannel resonance/car_lyrics_events。
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null

    /** 冷启动时随 Intent 带进来的文件（Dart 侧启动后主动取一次） */
    private var pendingUri: Uri? = null

    // ===== 车载蓝牙状态 =====
    private var carLyricsChannel: MethodChannel? = null
    private var carLyricsEvents: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var a2dpProxy: BluetoothProfile? = null
    private var headsetProxy: BluetoothProfile? = null
    private var receiverRegistered = false

    private val btManager: BluetoothManager by lazy {
        getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }

    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            emitCarState()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialUri" -> {
                        result.success(pendingUri?.toString())
                        pendingUri = null
                    }
                    "readText" -> {
                        val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
                        result.success(if (uri == null) null else readText(uri))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        setupCarLyrics(flutterEngine)
        setupPermissions(flutterEngine)
    }

    private var notifPermissionResult: MethodChannel.Result? = null

    private fun setupPermissions(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "resonance/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            notifPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_NOTIFICATION,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupCarLyrics(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        carLyricsChannel = MethodChannel(messenger, "resonance/car_lyrics").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "current" -> result.success(currentCarState())
                    "ensurePermission" -> {
                        ensureBtPermission()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        carLyricsEvents = EventChannel(messenger, "resonance/car_lyrics_events").also { ev ->
            ev.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    startBtMonitoring()
                    emitCarState()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    stopBtMonitoring()
                }
            })
        }
    }

    private fun hasBtPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun ensureBtPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasBtPermission()) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                REQ_BT_CONNECT,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_BT_CONNECT) emitCarState()
        if (requestCode == REQ_NOTIFICATION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            notifPermissionResult?.success(granted)
            notifPermissionResult = null
        }
    }

    private fun initProxies() {
        val adapter = btManager.adapter ?: return
        try {
            if (!adapter.isEnabled) return
            adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    when (profile) {
                        BluetoothProfile.A2DP -> a2dpProxy = proxy
                        BluetoothProfile.HEADSET -> headsetProxy = proxy
                    }
                    emitCarState()
                }

                override fun onServiceDisconnected(profile: Int) {
                    when (profile) {
                        BluetoothProfile.A2DP -> a2dpProxy = null
                        BluetoothProfile.HEADSET -> headsetProxy = null
                    }
                    emitCarState()
                }
            }, BluetoothProfile.A2DP)
            adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    headsetProxy = proxy
                    emitCarState()
                }

                override fun onServiceDisconnected(profile: Int) {
                    headsetProxy = null
                    emitCarState()
                }
            }, BluetoothProfile.HEADSET)
        } catch (_: SecurityException) {
            // 无权限：按未连接处理
        }
    }

    private fun connectedDevices(proxy: BluetoothProfile?): List<BluetoothDevice> = try {
        proxy?.connectedDevices ?: emptyList()
    } catch (_: SecurityException) {
        emptyList()
    }

    private fun currentCarState(): Map<String, Any?> {
        val adapter = btManager.adapter
        if (adapter == null || !adapter.isEnabled || !hasBtPermission()) {
            return mapOf(
                "bluetoothConnected" to false,
                "carDetected" to false,
                "deviceName" to null,
            )
        }
        val devices = (connectedDevices(a2dpProxy) + connectedDevices(headsetProxy))
            .distinctBy { it.address }
        val car = devices.any { dev ->
            try {
                dev.bluetoothClass?.deviceClass == BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO
            } catch (_: SecurityException) {
                false
            }
        }
        return mapOf(
            "bluetoothConnected" to devices.isNotEmpty(),
            "carDetected" to car,
            "deviceName" to devices.firstOrNull()?.name,
        )
    }

    private fun startBtMonitoring() {
        initProxies()
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }
        registerReceiver(btReceiver, filter)
        receiverRegistered = true
    }

    private fun stopBtMonitoring() {
        if (!receiverRegistered) return
        try {
            unregisterReceiver(btReceiver)
        } catch (_: Exception) {
            // 忽略
        }
        receiverRegistered = false
    }

    private fun emitCarState() {
        eventSink?.success(currentCarState())
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let { pendingUri = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { channel?.invokeMethod("openedUri", it.toString()) }
    }

    override fun onDestroy() {
        stopBtMonitoring()
        super.onDestroy()
    }

    /** 通过 ContentResolver 读文本（SAF 的 content:// 只有这里能读） */
    private fun readText(uri: Uri): String? = try {
        contentResolver.openInputStream(uri)?.use { input ->
            input.readBytes().toString(Charsets.UTF_8)
        }
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val CHANNEL = "resonance/open_file"
        private const val REQ_BT_CONNECT = 9001
        private const val REQ_NOTIFICATION = 9002
    }
}
