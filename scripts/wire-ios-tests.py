"""Add native XCTest targets without third-party project-editing dependencies.

Run once from the repository root. Stable IDs make the generated scheme reusable.
"""
from pathlib import Path

project = Path("smartmarket.xcodeproj/project.pbxproj")
text = project.read_text()
APP = "ADF8148B2FCA0F6400433335"
PROJECT = "ADF814842FCA0F6400433335"
targets = []

def insert(section, content):
    global text
    marker = f"/* End {section} section */"
    assert marker in text, section
    text = text.replace(marker, content + "\n" + marker)

for index, (name, path, kind) in enumerate([
    ("smartmarketTests", "smartmarketTests", "unit-test"),
    ("smartmarketUITests", "UITests", "ui-testing"),
], start=1):
    base = int(f"B{index}" + "0" * 22, 16)
    ids = {key: f"{base+n:024X}" for n, key in enumerate(
        ["target", "sources", "frameworks", "resources", "product", "group", "configs", "debug", "release", "dependency", "proxy"], start=1)}
    target = ids["target"]
    targets.append((name, target))
    if target in text:
        continue
    insert("PBXFileReference", f'\t\t{ids["product"]} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    insert("PBXFileSystemSynchronizedRootGroup", f'\t\t{ids["group"]} = {{isa = PBXFileSystemSynchronizedRootGroup; path = {path}; sourceTree = "<group>"; }};')
    for phase in ("sources", "frameworks", "resources"):
        section = {"sources": "PBXSourcesBuildPhase", "frameworks": "PBXFrameworksBuildPhase", "resources": "PBXResourcesBuildPhase"}[phase]
        insert(section, f'\t\t{ids[phase]} = {{isa = {section}; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};')
    insert("PBXNativeTarget", f'''\t\t{target} = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {ids["configs"]};
            buildPhases = ({ids["sources"]}, {ids["frameworks"]}, {ids["resources"]});
            buildRules = ();
            dependencies = ({ids["dependency"]});
            fileSystemSynchronizedGroups = ({ids["group"]});
            name = {name}; productName = {name};
            productReference = {ids["product"]};
            productType = "com.apple.product-type.bundle.{kind}";
        }};''')
    special = ('BUNDLE_LOADER = "$(TEST_HOST)"; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/smartmarket.app/smartmarket";'
               if kind == "unit-test" else "TEST_TARGET_NAME = smartmarket;")
    for config in ("debug", "release"):
        insert("XCBuildConfiguration", f'''\t\t{ids[config]} = {{
            isa = XCBuildConfiguration;
            buildSettings = {{
                CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = P36US5XNJ5;
                GENERATE_INFOPLIST_FILE = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0;
                PRODUCT_BUNDLE_IDENTIFIER = com.mostafa.mealio.{name};
                PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos;
                SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";
                LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks");
                {special}
            }};
            name = {config.capitalize()};
        }};''')
    insert("XCConfigurationList", f'\t\t{ids["configs"]} = {{isa = XCConfigurationList; buildConfigurations = ({ids["debug"]}, {ids["release"]}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
    dependency = f'''\t\t{ids["proxy"]} = {{isa = PBXContainerItemProxy; containerPortal = {PROJECT}; proxyType = 1; remoteGlobalIDString = {APP}; remoteInfo = smartmarket; }};
        {ids["dependency"]} = {{isa = PBXTargetDependency; target = {APP}; targetProxy = {ids["proxy"]}; }};
'''
    text = text.replace("/* Begin PBXBuildFile section */", dependency + "\n/* Begin PBXBuildFile section */")
    text = text.replace('\t\t\t\tADMAP0032FCA0F6400433335 /* Frameworks */,', f'                {ids["group"]},\n\t\t\t\tADMAP0032FCA0F6400433335 /* Frameworks */,')
    text = text.replace('\t\t\t\tADF8148C2FCA0F6400433335 /* smartmarket.app */,', f'                {ids["product"]},\n\t\t\t\tADF8148C2FCA0F6400433335 /* smartmarket.app */,')
    text = text.replace('targets = (', f'targets = (\n                {target},', 1)

project.write_text(text)

def reference(name, target):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.xctest" BlueprintName="{name}" ReferencedContainer="container:smartmarket.xcodeproj"/>'

appref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{APP}" BuildableName="smartmarket.app" BlueprintName="smartmarket" ReferencedContainer="container:smartmarket.xcodeproj"/>'
testables = "".join(f'<TestableReference skipped="NO">{reference(name, target)}</TestableReference>' for name, target in targets)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2650" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
destination = Path("smartmarket.xcodeproj/xcshareddata/xcschemes/smartmarket.xcscheme")
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(scheme)
print("Configured native unit/UI test targets and shared smartmarket scheme.")
