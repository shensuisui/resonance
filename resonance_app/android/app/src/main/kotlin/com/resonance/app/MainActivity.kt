package com.resonance.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity。
 *
 * 1) 继承 AudioServiceActivity（而不是 FlutterActivity）：音频后台服务与 Activity
 *    必须共用同一个 FlutterEngine，否则通知点开后会起第二个引擎/黑屏。
 * 2) 承担「用回响打开 .json」的入口：系统通过 ACTION_VIEW 把文件交进来，
 *    这里把内容读成文本推给 Dart（MethodChannel: resonance/open_file），
 *    Dart 侧解析成备份后走统一的导入流程。
 */
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null

    /** 冷启动时随 Intent 带进来的文件（Dart 侧启动后主动取一次） */
    private var pendingUri: Uri? = null

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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.data?.let { pendingUri = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App 已在运行时再「用回响打开」：直接推给 Dart（冷启动会稍后自己来取）
        intent.data?.let { channel?.invokeMethod("openedUri", it.toString()) }
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
    }
}
