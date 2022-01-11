import com.felipefzdz.gradle.shellcheck.Shellcheck

plugins {
    id("base")
    id("com.felipefzdz.gradle.shellcheck") version "1.4.6"
    id("com.github.breadmoirai.github-release") version "2.2.12"
}

repositories {
    exclusiveContent {
        forRepository {
            ivy {
                url = uri("https://github.com/matejak/")
                patternLayout {
                    artifact("[module]/archive/refs/tags/[revision].[ext]")
                }
                metadataSources {
                    artifact()
                }
            }
        }
        filter {
            includeModule("argbash", "argbash")
        }
    }
    mavenCentral()
}

val appVersion = layout.projectDirectory.file("release/version.txt").asFile.readText().trim()
allprojects {
    version = appVersion
}

val argbash by configurations.creating
val commonComponents by configurations.creating
val mavenComponents by configurations.creating

dependencies {
    argbash("argbash:argbash:2.10.0@zip")
    commonComponents(project(path = ":fetch-build-scan-data-cmdline-tool", configuration = "shadow"))
    mavenComponents(project(":capture-build-scan-url-maven-extension"))
    mavenComponents("com.gradle:gradle-enterprise-maven-extension:1.12")
    mavenComponents("com.gradle:common-custom-user-data-maven-extension:1.9")
}

shellcheck {
    additionalArguments = "-a -x"
    shellcheckVersion = "v0.7.2"
}

val unpackArgbash = tasks.register<Copy>("unpackArgbash") {
    group = "argbash"
    description = "Unpacks Argbash."
    from(zipTree(argbash.singleFile)) {
        // All files in the zip are under an "argbash-VERSION/" directory, but we really just want the files.
        // We can remove the top-level directory while unpacking the zip by dropping the first directory in each file's relative path.
        eachFile {
            relativePath = RelativePath(true, *relativePath.segments.drop(1).toTypedArray())
        }
        includeEmptyDirs = false
    }
    into(layout.buildDirectory.dir("argbash"))
}

val applyArgbash = tasks.register<ApplyArgbash>("generateBashCliParsers") {
    group = "argbash"
    description = "Uses Argbash to generate Bash command line argument parsing code."
    argbashHome.set(layout.dir(unpackArgbash.map { it.outputs.files.singleFile }))
    scriptTemplates.set(fileTree("components/scripts") {
        include("**/*-cli-parser.m4")
        exclude("gradle/.data/")
        exclude("maven/.data/")
    })
    supportingTemplates.set(fileTree("components/scripts") {
        include("**/*.m4")
        exclude("gradle/.data/")
        exclude("maven/.data/")
    })
}

val copyGradleScripts = tasks.register<Copy>("copyGradleScripts") {
    group = "build"
    description = "Copies the Gradle source and generated scripts to output directory."

    from(layout.projectDirectory.file("LICENSE"))
    from(layout.projectDirectory.dir("release").file("version.txt"))
    rename("version.txt", "VERSION")

    from(layout.projectDirectory.dir("components/scripts/gradle")) {
        exclude("gradle-init-scripts")
        filter { line: String -> line.replace("/../lib", "/lib").replace("<HEAD>","${project.version}") }
    }
    from(layout.projectDirectory.dir("components/scripts/gradle")) {
        include("gradle-init-scripts/**")
        into("lib/")
    }
    from(layout.projectDirectory.dir("components/scripts")) {
        include("README.md")
        include("lib/**")
        exclude("maven")
        exclude("lib/cli-parsers")
        filter { line: String -> line.replace("/../lib", "/lib").replace("<HEAD>","${project.version}") }
    }
    from(applyArgbash.map { it.outputDir.file("lib/cli-parsers/gradle") }) {
        into("lib/")
    }
    from(commonComponents) {
        into("lib/export-api-clients/")
    }
    into(layout.buildDirectory.dir("scripts/gradle"))
}

val copyMavenScripts = tasks.register<Copy>("copyMavenScripts") {
    group = "build"
    description = "Copies the Maven source and generated scripts to output directory."

    from(layout.projectDirectory.file("LICENSE"))
    from(layout.projectDirectory.dir("release").file("version.txt"))
    rename("version.txt", "VERSION")

    from(layout.projectDirectory.dir("components/scripts/maven")) {
        filter { line: String -> line.replace("/../lib", "/lib").replace("<HEAD>","${project.version}") }
    }
    from(layout.projectDirectory.dir("components/scripts/")) {
        include("README.md")
        include("lib/**")
        exclude("gradle")
        exclude("lib/cli-parsers")
        filter { line: String -> line.replace("/../lib", "/lib").replace("<HEAD>","${project.version}") }
    }
    from(applyArgbash.map { it.outputDir.file("lib/cli-parsers/maven") }) {
        into("lib/")
    }
    from(commonComponents) {
        into("lib/export-api-clients/")
    }
    from(mavenComponents) {
        into("lib/maven-libs/")
    }
    into(layout.buildDirectory.dir("scripts/maven"))
}

tasks.register<Task>("copyScripts") {
    group = "build"
    description = "Copies source scripts and autogenerated scripts to output directory."
    dependsOn("copyGradleScripts")
    dependsOn("copyMavenScripts")
}

tasks.register<Zip>("assembleGradleScripts") {
    group = "build"
    description = "Packages the Gradle experiment scripts in a zip archive."
    archiveBaseName.set("gradle-enterprise-gradle-build-validation")
    archiveFileName.set("${archiveBaseName.get()}.zip")
    from(copyGradleScripts)
    into(archiveBaseName.get())
}

tasks.register<Zip>("assembleMavenScripts") {
    group = "build"
    description = "Packages the Maven experiment scripts in a zip archive."
    archiveBaseName.set("gradle-enterprise-maven-build-validation")
    archiveFileName.set("${archiveBaseName.get()}.zip")
    from(copyMavenScripts)
    into(archiveBaseName.get())
}

tasks.named("assemble") {
    dependsOn("assembleGradleScripts")
    dependsOn("assembleMavenScripts")
}

tasks.register<Shellcheck>("shellcheckGradleScripts") {
    group = "verification"
    description = "Perform quality checks on Gradle build validation scripts using Shellcheck."
    sourceFiles = copyGradleScripts.get().outputs.files.asFileTree.matching {
        include("**/*.sh")
        exclude("lib/")
    }
    workingDir = file("${buildDir}/scripts/gradle")
    reports {
        html.outputLocation.set(file("${buildDir}/reports/shellcheck-gradle/shellcheck.html"))
        xml.outputLocation.set(file("${buildDir}/reports/shellcheck-gradle/shellcheck.xml"))
        txt.outputLocation.set(file("${buildDir}/reports/shellcheck-gradle/shellcheck.txt"))
    }
}

tasks.register<Shellcheck>("shellcheckMavenScripts") {
    group = "verification"
    description = "Perform quality checks on Maven build validation scripts using Shellcheck."
    sourceFiles = copyMavenScripts.get().outputs.files.asFileTree.matching {
        include("**/*.sh")
        exclude("lib/")
    }
    workingDir = file("${buildDir}/scripts/maven")
    reports {
        html.outputLocation.set(file("${buildDir}/reports/shellcheck-maven/shellcheck.html"))
        xml.outputLocation.set(file("${buildDir}/reports/shellcheck-maven/shellcheck.xml"))
        txt.outputLocation.set(file("${buildDir}/reports/shellcheck-maven/shellcheck.txt"))
    }
}

tasks.named("check") {
    dependsOn("shellcheckGradleScripts")
    dependsOn("shellcheckMavenScripts")
}

val isDevelopmentRelease = !hasProperty("finalRelease")

githubRelease {
    token((findProperty("github.access.token") ?: System.getenv("GITHUB_ACCESS_TOKEN") ?: "").toString())
    releaseName.set(if (isDevelopmentRelease) "Development Build" else version.toString())
    owner.set("gradle")
    repo.set("gradle-enterprise-build-validation-scripts")
    targetCommitish.set("main")
    tagName.set(releaseTag())
    prerelease.set(isDevelopmentRelease)
    overwrite.set(isDevelopmentRelease)
    body.set(layout.projectDirectory.file("release/changes.md").asFile.readText().trim())
    releaseAssets(tasks.getByName("assembleGradleScripts"), tasks.getByName("assembleMavenScripts"))
}

tasks.register<CreateGitTag>("createReleaseTag") {
    tagName.set(releaseTag())
    overwriteExisting.set(isDevelopmentRelease)
}

tasks.named("githubRelease") {
    dependsOn("createReleaseTag")
}

fun releaseTag(): String {
    if (isDevelopmentRelease) {
        return "development-latest"
    }
    return "v${version}"
}
