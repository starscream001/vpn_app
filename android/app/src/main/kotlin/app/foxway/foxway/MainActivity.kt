package app.foxway.foxway

import android.app.Activity
import android.content.Context
import android.os.Build
import android.net.Uri
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.io.File
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.backend.TunnelActionHandler
import org.amnezia.awg.config.Config
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null
    private val tunnel = object : Tunnel {
        override fun getName() = "FoxWay"
        override fun isIpv4ResolutionPreferred() = true
        override fun isMetered() = false
        override fun onStateChange(newState: Tunnel.State) {}
    }
    private val backend by lazy {
        GoBackend(applicationContext, object : TunnelActionHandler {
            override fun runPreUp(scripts: Collection<String>) {}
            override fun runPostUp(scripts: Collection<String>) {}
            override fun runPreDown(scripts: Collection<String>) {}
            override fun runPostDown(scripts: Collection<String>) {}
        })
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.foxway/tunnel")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installUpdate" -> {
                        try {
                            val source = File(call.argument<String>("path") ?: "").canonicalFile
                            if (!source.path.startsWith(cacheDir.canonicalPath + "/") || !source.name.endsWith(".apk")) throw IllegalArgumentException()
                            val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                            val archive = packageManager.getPackageArchiveInfo(source.path, flags) ?: throw IllegalArgumentException()
                            val current = packageManager.getPackageInfo(packageName, flags)
                            val version = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
                            val installedVersion = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
                            @Suppress("DEPRECATION")
                            val a = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
                            @Suppress("DEPRECATION")
                            val b = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
                            if (archive.packageName != packageName || version <= installedVersion || a == null || b == null || a.map { it.toCharsString() }.sorted() != b.map { it.toCharsString() }.sorted()) {
                                result.error("SIGNATURE", "Новая версия подписана другим ключом или не является обновлением. Установка отменена; данные сохранены.", null)
                            } else if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                startActivity(Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES", Uri.parse("package:$packageName")))
                                result.error("INSTALL_PERMISSION", "Разрешите обновления FoxWay и повторите установку", null)
                            } else {
                                val folder = File(cacheDir, "updates"); folder.mkdirs()
                                val target = File(folder, "update.apk"); source.copyTo(target, overwrite=true)
                                val uri = FileProvider.getUriForFile(this, "$packageName.updates", target)
                                startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(null)
                            }
                        } catch (_: Exception) { result.error("UPDATE", "Не удалось открыть проверенный APK", null) }
                    }
                    "protectionStatus" -> {
                        try {
                            val probe = VpnPolicyProbe(applicationContext)
                            result.success(if (Build.VERSION.SDK_INT >= 29) mapOf("lockdown" to probe.isLockdownEnabled, "alwaysOn" to probe.isAlwaysOn) else mapOf("lockdown" to false, "unsupported" to true))
                        } catch (_: Exception) { result.success(mapOf("lockdown" to false)) }
                    }
                    "apps" -> {
                        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val apps = packageManager.queryIntentActivities(launcher, 0)
                            .filter { it.activityInfo.packageName != packageName }
                            .map { mapOf("id" to it.activityInfo.packageName,
                                "name" to it.loadLabel(packageManager).toString()) }
                            .distinctBy { it["id"] }.sortedBy { it["name"] }
                        result.success(apps)
                    }
                    "settings" -> {
                        startActivity(Intent("android.settings.VPN_SETTINGS")); result.success(null)
                    }
                    "start" -> {
                        if (pending != null) { result.error("BUSY", "VPN permission pending", null); return@setMethodCallHandler }
                        val raw = call.argument<String>("config") ?: ""
                        // No executable hooks from third-party configs, ever.
                        if (Regex("(?im)^\\s*(PreUp|PostUp|PreDown|PostDown|IncludedApplications|ExcludedApplications)\\s*=").containsMatchIn(raw)) {
                            result.error("CONFIG", "Unsafe config directive", null); return@setMethodCallHandler
                        }
                        val excluded = call.argument<List<String>>("excludedApps") ?: emptyList()
                        val action = {
                            worker.execute {
                                try {
                                    val safeExcluded = excluded.filter { it != packageName && it.matches(Regex("[A-Za-z0-9_.]+")) }
                                    val patched = if (safeExcluded.isEmpty()) raw else raw.replaceFirst("[Peer]", "ExcludedApplications = " + safeExcluded.joinToString(", ") + "\n[Peer]")
                                    val config = Config.parse(ByteArrayInputStream(patched.toByteArray()))
                                    startForegroundService(Intent(this, TunnelKeeper::class.java))
                                    backend.setState(tunnel, Tunnel.State.UP, config)
                                    runOnUiThread { result.success(null) }
                                } catch (_: Exception) {
                                    stopService(Intent(this, TunnelKeeper::class.java))
                                    runOnUiThread { result.error("VPN_START", "AmneziaWG could not start; check profile and permission", null) }
                                }
                            }
                            Unit
                        }
                        val permission = VpnService.prepare(this)
                        if (permission != null) {
                            pending = action; permissionResult = result; startActivityForResult(permission, 104)
                        } else action()
                    }
                    "stop" -> worker.execute {
                        try {
                            backend.setState(tunnel, Tunnel.State.DOWN, null)
                            stopService(Intent(this, TunnelKeeper::class.java))
                            runOnUiThread { result.success(null) }
                        } catch (_: Exception) { runOnUiThread { result.error("VPN_STOP", "Could not stop tunnel", null) } }
                    }
                    "stats" -> worker.execute {
                        try {
                            val stats = backend.getStatistics(tunnel)
                            val up = backend.getState(tunnel) == Tunnel.State.UP
                            runOnUiThread { result.success(mapOf("rx" to stats.totalRx(), "tx" to stats.totalTx(), "up" to up)) }
                        } catch (_: Exception) { runOnUiThread { result.success(mapOf("rx" to 0L, "tx" to 0L, "up" to false)) } }
                    }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 104) {
            val action = pending; val result = permissionResult
            pending = null; permissionResult = null
            if (resultCode == Activity.RESULT_OK) action?.invoke()
            else result?.error("PERMISSION", "VPN permission denied", null)
        }
    }
}

// Public VpnService policy APIs use the app Context/UID; no VPN is created by this probe.
private class VpnPolicyProbe(context: Context) : VpnService() { init { attachBaseContext(context) } }
