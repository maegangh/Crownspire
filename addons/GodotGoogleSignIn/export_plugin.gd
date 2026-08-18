@tool
extends EditorPlugin

## Android export hook for Credential Manager Google Sign-In.
## AAR: addons/GodotGoogleSignIn/bin/release/GodotGoogleSignIn-release.aar
## Runtime still requires the Web OAuth client ID (gitignored local cfg).

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := "GodotGoogleSignIn"

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform, _debug) -> PackedStringArray:
		return PackedStringArray([
			_plugin_name + "/bin/release/" + _plugin_name + "-release.aar",
		])

	func _get_android_dependencies(_platform, _debug) -> PackedStringArray:
		return PackedStringArray([
			"androidx.credentials:credentials:1.3.0",
			"androidx.credentials:credentials-play-services-auth:1.3.0",
			"com.google.android.libraries.identity.googleid:googleid:1.1.1",
			"org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3",
		])

	func _get_name() -> String:
		return _plugin_name
