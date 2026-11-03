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

// 部分第三方插件（如 audiotags 1.4.5）仍写死 compileSdkVersion 31，而它们依赖的
// AndroidX 组件要求 34+，AGP 9 的 checkReleaseAarMetadata 会让 release 构建失败。
// 这里把插件子工程的 compileSdk 统一抬到与 app 一致的 36（Flutter 3.47 默认值）。
// 用 Groovy 动态调用，避免绑定 AGP 的 DSL 类型（AGP 版本升级不会让脚本编译失败）。
subprojects {
    afterEvaluate {
        if (project.name == "app") return@afterEvaluate
        if (!project.plugins.hasPlugin("com.android.library")) return@afterEvaluate
        project.extensions.findByName("android")?.withGroovyBuilder {
            "compileSdkVersion"(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
