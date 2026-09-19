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

// compileSdk 抬升至 36 的逻辑已迁移到 init-scripts/raise-compile-sdk.gradle：
// 部分插件（如 file_picker 8.3.7）将 compileSdk 硬编码为 34，不随
// flutter.compileSdkVersion 变化，而其传递依赖 flutter_plugin_android_lifecycle 2.0.35
// 的 AAR 仅要求 compileSdk>=36；若插件仍以 34 编译，CheckAarMetadata 校验会失败。
// init-scripts 由 Gradle 在所有项目配置前加载，能在插件完成配置后安全地抬升 compileSdk，
// 避免在根构建脚本中手动调用 afterEvaluate 触发
// "Cannot run Project.afterEvaluate(Action) when the project is already evaluated"。

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
