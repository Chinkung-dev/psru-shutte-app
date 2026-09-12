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
    if (name == "app") {
        // ให้ Flutter engine ตรงกับ ABI ที่แอปรองรับ แม้ IDE เลือก emulator x86_64
        // ปลั๊กอินกราฟิก 3D ของชุดนี้ใช้ ARM64; emulator ต้องรองรับ ARM translation
        extensions.extraProperties.set("target-platform", "android-arm64")
    }
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
