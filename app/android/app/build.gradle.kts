import java.io.File
import java.util.Properties
import org.gradle.api.tasks.Exec

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- Release 签名：从 android/key.properties 读取（由 CI secrets 生成）----
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.emote.app.emote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // applicationId 与组织标识 com.emote.app 对齐（README 中的包名）
        applicationId = "com.emote.app"
        // 项目约束的 Android minSdk
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists() && keystoreProperties["storeFile"] != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists() && keystoreProperties["storeFile"] != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// ============================================================================
// Emote Rust core（emote_core）交叉编译并打包进 APK jniLibs
// ============================================================================
val sdkDir: String = project.findProperty("sdk.dir") as? String
    ?: System.getenv("ANDROID_SDK_ROOT")
    ?: System.getenv("ANDROID_HOME")
    ?: "/opt/android-sdk"

val ndkRoot = File(sdkDir, "ndk")
val ndkDir = if (ndkRoot.isDirectory) {
    ndkRoot.listFiles()?.filter { it.isDirectory }?.firstOrNull()
} else {
    null
}

// Rust crate 根目录：app/android/../../rust/emote_core
val rustRoot = file("${rootDir}/../..").resolve("rust/emote_core")

// 目标 ABI → (Rust target, NDK clang 前缀)
val abiMap = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "armv7-linux-androideabi",
    "x86_64" to "x86_64-linux-android",
)

val buildRustAndroid by tasks.registering {
    group = "emote"
    description = "交叉编译 emote_core 到 Android ABIs 并放入 jniLibs"
}

// 先清除旧产物，避免残留其他 ABI
val cleanJniLibs = tasks.register("cleanEmoteJniLibs") {
    doLast {
        project.delete(file("src/main/jniLibs/emote"))
    }
}

val rustTasks = mutableListOf<Task>()
for ((abi, rustTarget) in abiMap) {
    val linkerEnvKey = "CARGO_TARGET_" + rustTarget.uppercase().replace('-', '_') + "_LINKER"
    val taskName = "cargoBuildAndroid$abi"
    val task = tasks.register(taskName, Exec::class) {
        group = "emote"
        description = "构建 emote_core ($abi)"
        workingDir = rustRoot
        commandLine(
            "cargo", "build", "--release",
            "--target", rustTarget,
            "--manifest-path", "${rustRoot}/Cargo.toml",
        )
        val llvmBin = ndkDir?.let { File(it, "toolchains/llvm/prebuilt/linux-x86_64/bin").absolutePath }
        if (llvmBin != null) {
            environment(linkerEnvKey, "$llvmBin/${when (rustTarget) {
                "aarch64-linux-android" -> "aarch64-linux-android24-clang"
                "armv7-linux-androideabi" -> "armv7a-linux-androideabi24-clang"
                else -> "x86_64-linux-android24-clang"
            }}")
            // cc crate 需要 CC/AR 指向 NDK 交叉编译器（cargo 约定：CC_<target> 小写下划线）
            environment("CC_${rustTarget.replace('-', '_')}", "$llvmBin/${when (rustTarget) {
                "aarch64-linux-android" -> "aarch64-linux-android24-clang"
                "armv7-linux-androideabi" -> "armv7a-linux-androideabi24-clang"
                else -> "x86_64-linux-android24-clang"
            }}")
            environment("AR_${rustTarget.replace('-', '_')}", "$llvmBin/${when (rustTarget) {
                "aarch64-linux-android" -> "llvm-ar"
                "armv7-linux-androideabi" -> "llvm-ar"
                else -> "llvm-ar"
            }}")
            environment("ANDROID_NDK_HOME", ndkDir.absolutePath)
            environment("CARGO_TARGET_DIR", "${rootDir}/rust-android-target")
        } else {
            doLast { throw GradleException("未找到 Android NDK，无法交叉编译 emote_core") }
        }
        doLast {
            val srcSo = File(rustRoot, "target/$rustTarget/release/libemote_core.so")
            val dstSo = file("src/main/jniLibs/emote/$abi/libemote_core.so")
            if (!srcSo.exists()) {
                throw GradleException("未找到 $srcSo")
            }
            dstSo.parentFile?.mkdirs()
            srcSo.copyTo(dstSo, overwrite = true)
            println("emote_core ($abi) -> ${dstSo.absolutePath}")
        }
    }
    task.configure {
        dependsOn(cleanJniLibs)
    }
    buildRustAndroid.configure { dependsOn(task) }
}

// 让所有 assemble 任务在打包前先构建 Rust 库
tasks.configureEach {
    if (name == "mergeReleaseJniLibFolders" || name == "mergeDebugJniLibFolders") {
        dependsOn(buildRustAndroid)
    }
}