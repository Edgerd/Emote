allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 部分插件（如 file_picker 8.3.7）把 compileSdk 硬编码为 34，不随
// flutter.compileSdkVersion 变化；其传递依赖 flutter_plugin_android_lifecycle 2.0.35
// 的 AAR 仅要求 compileSdk>=36。这里在评估后统一把 app 与全部插件子项目（library/
// application）的 compileSdk 抬到 36，使 CheckAarMetadata 校验通过。
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = 36
            }
        } else if (plugins.hasPlugin("com.android.application")) {
            extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
                compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
