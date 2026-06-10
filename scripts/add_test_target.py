#!/usr/bin/env python3
from pathlib import Path

pbx = Path(__file__).resolve().parents[1] / "AproposMagazinev2.xcodeproj/project.pbxproj"
text = pbx.read_text()
if "FFTEST022EBCFD440025EC07" in text:
    print("Test target already present")
    raise SystemExit(0)

replacements = [
(
"/* End PBXFileReference section */",
"""		FFTEST012EBCFD440025EC07 /* AproposMagazineTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = AproposMagazineTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */"""
),
(
"/* End PBXContainerItemProxy section */",
"""		FFTEST062EBCFD440025EC07 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = B68382122E056B2F005C4E85 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = B68382192E056B2F005C4E85;
			remoteInfo = AproposMagazinev2;
		};
/* End PBXContainerItemProxy section */"""
),
(
"/* End PBXFrameworksBuildPhase section */",
"""		FFTEST052EBCFD440025EC07 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */"""
),
(
"/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
"""/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		FFTEST032EBCFD440025EC07 /* AproposMagazineTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = AproposMagazineTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */"""
),
(
"\t\t\t\tB683821C2E056B2F005C4E85 /* AproposMagazinev2 */,\n\t\t\t\tB683821B2E056B2F005C4E85 /* Products */,",
"""\t\t\t\tB683821C2E056B2F005C4E85 /* AproposMagazinev2 */,
\t\t\t\tFFTEST032EBCFD440025EC07 /* AproposMagazineTests */,
\t\t\t\tB683821B2E056B2F005C4E85 /* Products */,"""
),
(
"\t\t\t\tEEWIDGET032EBCFD440025EC07 /* AproposMagazineWidget.appex */,\n\t\t\t);",
"""\t\t\t\tEEWIDGET032EBCFD440025EC07 /* AproposMagazineWidget.appex */,
\t\t\t\tFFTEST012EBCFD440025EC07 /* AproposMagazineTests.xctest */,
\t\t\t);"""
),
(
"/* End PBXNativeTarget section */",
"""		FFTEST022EBCFD440025EC07 /* AproposMagazineTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = FFTEST082EBCFD440025EC07 /* Build configuration list for PBXNativeTarget "AproposMagazineTests" */;
			buildPhases = (
				FFTEST042EBCFD440025EC07 /* Sources */,
				FFTEST052EBCFD440025EC07 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				FFTEST072EBCFD440025EC07 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				FFTEST032EBCFD440025EC07 /* AproposMagazineTests */,
			);
			name = AproposMagazineTests;
			packageProductDependencies = (
			);
			productName = AproposMagazineTests;
			productReference = FFTEST012EBCFD440025EC07 /* AproposMagazineTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */"""
),
(
"\t\t\t\tEEWIDGET022EBCFD440025EC07 /* AproposMagazineWidget */,\n\t\t\t);",
"""\t\t\t\tEEWIDGET022EBCFD440025EC07 /* AproposMagazineWidget */,
\t\t\t\tFFTEST022EBCFD440025EC07 /* AproposMagazineTests */,
\t\t\t);"""
),
(
"/* End PBXSourcesBuildPhase section */",
"""		FFTEST042EBCFD440025EC07 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */"""
),
(
"/* End PBXTargetDependency section */",
"""		FFTEST072EBCFD440025EC07 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = B68382192E056B2F005C4E85 /* AproposMagazinev2 */;
			targetProxy = FFTEST062EBCFD440025EC07 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */"""
),
(
"/* End XCBuildConfiguration section */",
"""		FFTEST092EBCFD440025EC07 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = Q2LR5XQ8GK;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.aproposmagazine.app.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Apropos Magazine.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Apropos Magazine";
			};
			name = Debug;
		};
		FFTEST0A2EBCFD440025EC07 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = Q2LR5XQ8GK;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@loader_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.aproposmagazine.app.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Apropos Magazine.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Apropos Magazine";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */"""
),
(
"/* End XCConfigurationList section */",
"""		FFTEST082EBCFD440025EC07 /* Build configuration list for PBXNativeTarget "AproposMagazineTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				FFTEST092EBCFD440025EC07 /* Debug */,
				FFTEST0A2EBCFD440025EC07 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */"""
),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"Missing anchor: {old[:80]!r}")
    text = text.replace(old, new, 1)

text = text.replace(
"""					EEWIDGET022EBCFD440025EC07 = {
						CreatedOnToolsVersion = 26.0.1;
						DevelopmentTeam = Q2LR5XQ8GK;
						SystemCapabilities = {
							com.apple.ApplicationGroups.iOS = {
								enabled = 1;
							};
						};
					};
				};""",
"""					EEWIDGET022EBCFD440025EC07 = {
						CreatedOnToolsVersion = 26.0.1;
						DevelopmentTeam = Q2LR5XQ8GK;
						SystemCapabilities = {
							com.apple.ApplicationGroups.iOS = {
								enabled = 1;
							};
						};
					};
					FFTEST022EBCFD440025EC07 = {
						CreatedOnToolsVersion = 26.0.1;
						DevelopmentTeam = Q2LR5XQ8GK;
						TestTargetID = B68382192E056B2F005C4E85;
					};
				};"""
)

pbx.write_text(text)
print("Added AproposMagazineTests target")
