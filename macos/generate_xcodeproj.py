#!/usr/bin/env python3
import os
import uuid

root = os.path.dirname(os.path.abspath(__file__))
app_dir = os.path.join(root, "PortMaster")
test_dir = os.path.join(root, "PortMasterTests")


def walk_swift(base):
    out = []
    for dirpath, _, files in os.walk(base):
        for f in sorted(files):
            if f.endswith((".swift", ".c", ".h")):
                rel = os.path.relpath(os.path.join(dirpath, f), root)
                out.append(rel.replace("\\", "/"))
    return sorted(out)


def walk_tests(base):
    return sorted(f"PortMasterTests/{f}" for f in os.listdir(base) if f.endswith(".swift"))


sources = walk_swift(app_dir)
tests = walk_tests(test_dir)


def uid():
    return uuid.uuid4().hex[:24].upper()


proj = uid()
target_app = uid()
target_test = uid()
config_dbg = uid()
config_rel = uid()
list_app = uid()
list_test = uid()
products_group = uid()
project_config_list = uid()
product_app = uid()
product_test = uid()
group_root = uid()
group_app = uid()
group_tests = uid()
build_app_frameworks = uid()
build_test_frameworks = uid()
build_app_sources = uid()
build_test_sources = uid()
build_test_target = uid()
build_test_target2 = uid()
build_app_run = uid()
build_app_run2 = uid()
build_test_run = uid()
build_test_run2 = uid()
build_app_frameworks2 = uid()
build_test_frameworks2 = uid()

file_refs = {}
build_files = {}
for path in sources + tests:
    file_refs[path] = uid()
    build_files[path] = uid()

lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")
lines.append("")
lines.append("/* Begin PBXBuildFile section */")
for path in sources + tests:
    bid = build_files[path]
    name = os.path.basename(path)
    fid = file_refs[path]
    lines.append(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};")
lines.append("/* End PBXBuildFile section */")
lines.append("")
lines.append("/* Begin PBXFileReference section */")
for path, fid in file_refs.items():
    name = os.path.basename(path)
    if path.endswith(".c"):
        t = "sourcecode.c.c"
    elif path.endswith(".h"):
        t = "sourcecode.c.h"
    else:
        t = "sourcecode.swift"
    rel = path.split("/", 1)[1] if path.startswith("PortMaster/") else name
    lines.append(
        f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {rel}; sourceTree = \"<group>\"; }};"
    )
lines.append(
    f"\t\t{product_app} /* PortMaster.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PortMaster.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
lines.append(
    f"\t\t{product_test} /* PortMasterTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PortMasterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
lines.append("/* End PBXFileReference section */")
lines.append("")
lines.append("/* Begin PBXFrameworksBuildPhase section */")
for fid in (build_app_frameworks, build_test_frameworks):
    lines.append(f"\t\t{fid} /* Frameworks */ = {{")
    lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
lines.append("/* End PBXFrameworksBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXGroup section */")
lines.append(f"\t\t{group_root} = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{group_app} /* PortMaster */,")
lines.append(f"\t\t\t\t{group_tests} /* PortMasterTests */,")
lines.append(f"\t\t\t\t{products_group} /* Products */,")
lines.append("\t\t\t);")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append(f"\t\t{group_app} /* PortMaster */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for path in sources:
    lines.append(f"\t\t\t\t{file_refs[path]} /* {os.path.basename(path)} */,")
lines.append("\t\t\t);")
lines.append("\t\t\tpath = PortMaster;")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append(f"\t\t{group_tests} /* PortMasterTests */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
for path in tests:
    rel = os.path.basename(path)
    lines.append(f"\t\t\t\t{file_refs[path]} /* {rel} */,")
lines.append("\t\t\t);")
lines.append("\t\t\tpath = PortMasterTests;")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append(f"\t\t{products_group} /* Products */ = {{")
lines.append("\t\t\tisa = PBXGroup;")
lines.append("\t\t\tchildren = (")
lines.append(f"\t\t\t\t{product_app} /* PortMaster.app */,")
lines.append(f"\t\t\t\t{product_test} /* PortMasterTests.xctest */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = Products;")
lines.append('\t\t\tsourceTree = "<group>";')
lines.append("\t\t};")
lines.append("/* End PBXGroup section */")
lines.append("")
lines.append("/* Begin PBXNativeTarget section */")
lines.append(f"\t\t{target_app} /* PortMaster */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {list_app} /* Build configuration list for PBXNativeTarget \"PortMaster\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{build_app_sources} /* Sources */,")
lines.append(f"\t\t\t\t{build_app_frameworks2} /* Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = ();")
lines.append("\t\t\tdependencies = ();")
lines.append("\t\t\tname = PortMaster;")
lines.append("\t\t\tproductName = PortMaster;")
lines.append(f"\t\t\tproductReference = {product_app} /* PortMaster.app */;")
lines.append('\t\t\tproductType = "com.apple.product-type.application";')
lines.append("\t\t};")
lines.append(f"\t\t{target_test} /* PortMasterTests */ = {{")
lines.append("\t\t\tisa = PBXNativeTarget;")
lines.append(f"\t\t\tbuildConfigurationList = {list_test} /* Build configuration list for PBXNativeTarget \"PortMasterTests\" */;")
lines.append("\t\t\tbuildPhases = (")
lines.append(f"\t\t\t\t{build_test_sources} /* Sources */,")
lines.append(f"\t\t\t\t{build_test_frameworks2} /* Frameworks */,")
lines.append("\t\t\t);")
lines.append("\t\t\tbuildRules = ();")
lines.append("\t\t\tdependencies = (")
lines.append(f"\t\t\t\t{build_test_target} /* PBXTargetDependency */,")
lines.append("\t\t\t);")
lines.append("\t\t\tname = PortMasterTests;")
lines.append("\t\t\tproductName = PortMasterTests;")
lines.append(f"\t\t\tproductReference = {product_test} /* PortMasterTests.xctest */;")
lines.append('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
lines.append("\t\t};")
lines.append("/* End PBXNativeTarget section */")
lines.append("")
lines.append("/* Begin PBXProject section */")
lines.append(f"\t\t{proj} /* Project object */ = {{")
lines.append("\t\t\tisa = PBXProject;")
lines.append("\t\t\tattributes = {")
lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
lines.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
lines.append("\t\t\t\tLastUpgradeCheck = 1600;")
lines.append("\t\t\t};")
lines.append(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"PortMaster\" */;")
lines.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
lines.append("\t\t\tdevelopmentRegion = en;")
lines.append("\t\t\thasScannedForEncodings = 0;")
lines.append("\t\t\tknownRegions = (")
lines.append("\t\t\t\ten,")
lines.append("\t\t\t\tBase,")
lines.append("\t\t\t);")
lines.append(f"\t\t\tmainGroup = {group_root};")
lines.append(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
lines.append('\t\t\tprojectDirPath = "";')
lines.append('\t\t\tprojectRoot = "";')
lines.append("\t\t\ttargets = (")
lines.append(f"\t\t\t\t{target_app} /* PortMaster */,")
lines.append(f"\t\t\t\t{target_test} /* PortMasterTests */,")
lines.append("\t\t\t);")
lines.append("\t\t};")
lines.append("/* End PBXProject section */")
lines.append("")
lines.append("/* Begin PBXSourcesBuildPhase section */")
for phase_id, paths in ((build_app_sources, sources), (build_test_sources, tests)):
    lines.append(f"\t\t{phase_id} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for path in paths:
        lines.append(f"\t\t\t\t{build_files[path]} /* {os.path.basename(path)} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
lines.append("/* End PBXSourcesBuildPhase section */")
lines.append("")
lines.append("/* Begin PBXContainerItemProxy section */")
lines.append(f"\t\t{build_test_target2} /* PBXContainerItemProxy */ = {{")
lines.append("\t\t\tisa = PBXContainerItemProxy;")
lines.append(f"\t\t\tcontainerPortal = {proj} /* Project object */;")
lines.append("\t\t\tproxyType = 1;")
lines.append(f"\t\t\tremoteGlobalIDString = {target_app};")
lines.append("\t\t\tremoteInfo = PortMaster;")
lines.append("\t\t};")
lines.append("/* End PBXContainerItemProxy section */")
lines.append("")
lines.append("/* Begin PBXTargetDependency section */")
lines.append(f"\t\t{build_test_target} /* PBXTargetDependency */ = {{")
lines.append("\t\t\tisa = PBXTargetDependency;")
lines.append(f"\t\t\ttarget = {target_app} /* PortMaster */;")
lines.append(f"\t\t\ttargetProxy = {build_test_target2} /* PBXContainerItemProxy */;")
lines.append("\t\t};")
lines.append("/* End PBXTargetDependency section */")
lines.append("")
lines.append("/* Begin XCBuildConfiguration section */")
for cid, name, extra in [
    (config_dbg, "Debug", "DEBUG_INFORMATION_FORMAT = dwarf;\n\t\t\t\tENABLE_TESTABILITY = YES;\n\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n\t\t\t\tONLY_ACTIVE_ARCH = YES;\n\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"),
    (config_rel, "Release", "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";"),
]:
    lines.append(f"\t\t{cid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCOPY_PHASE_STRIP = NO;")
    lines.append(f"\t\t\t\t{extra}")
    lines.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    lines.append("\t\t\t\tSDKROOT = macosx;")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

for cid, name in ((build_app_run, "Debug"), (build_app_run2, "Release")):
    lines.append(f"\t\t{cid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tCODE_SIGN_ENTITLEMENTS = PortMaster/PortMaster.entitlements;")
    lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
    lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    lines.append("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
    lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    lines.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = PortMaster;")
    lines.append("\t\t\t\tINFOPLIST_KEY_LSMinimumSystemVersion = 14.0;")
    lines.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
    lines.append('\t\t\t\t\t"$(inherited)",')
    lines.append('\t\t\t\t\t"@executable_path/../Frameworks",')
    lines.append("\t\t\t\t);")
    lines.append("\t\t\t\tMARKETING_VERSION = 0.1.0;")
    lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.portmaster.app;")
    lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    lines.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
    lines.append('\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "PortMaster/PortMaster-Bridging-Header.h";')
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")

for cid, name in ((build_test_run, "Debug"), (build_test_run2, "Release")):
    lines.append(f"\t\t{cid} /* {name} */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append('\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";')
    lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
    lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
    lines.append("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
    lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.portmaster.app.tests;")
    lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append('\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/PortMaster.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PortMaster";')
    lines.append("\t\t\t};")
    lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t};")
lines.append("/* End XCBuildConfiguration section */")
lines.append("")
lines.append("/* Begin XCConfigurationList section */")
for lid, name, cfgs in (
    (list_app, "PortMaster", (build_app_run, build_app_run2)),
    (list_test, "PortMasterTests", (build_test_run, build_test_run2)),
    (project_config_list, "PortMaster project", (config_dbg, config_rel)),
):
    label = "PBXProject" if lid == project_config_list else "PBXNativeTarget"
    lines.append(f"\t\t{lid} /* Build configuration list for {label} \"{name}\" */ = {{")
    lines.append("\t\t\tisa = XCConfigurationList;")
    lines.append("\t\t\tbuildConfigurations = (")
    for cfg in cfgs:
        if cfg in (config_dbg, build_app_run, build_test_run):
            lines.append(f"\t\t\t\t{cfg} /* Debug */,")
        else:
            lines.append(f"\t\t\t\t{cfg} /* Release */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    lines.append("\t\t\tdefaultConfigurationName = Release;")
    lines.append("\t\t};")
lines.append("/* End XCConfigurationList section */")
lines.append("\t};")
lines.append(f"\trootObject = {proj} /* Project object */;")
lines.append("}")

out = os.path.join(root, "PortMaster.xcodeproj", "project.pbxproj")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
print(f"Wrote {out} with {len(sources)} app sources and {len(tests)} tests")
