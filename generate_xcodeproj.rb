#!/usr/bin/env ruby
# Generates a minimal but valid Xcode project for PhotoTake iOS
require 'fileutils'

PROJECT_DIR = File.join(__dir__, 'PhotoTake')
XCODEPROJ_DIR = File.join(PROJECT_DIR, 'PhotoTake.xcodeproj')
FileUtils.mkdir_p(XCODEPROJ_DIR)

# All Swift source files relative to PhotoTake/PhotoTake/
SOURCES = %w[
  PhotoTakeApp.swift
  CameraModule/CameraSession.swift
  CameraModule/CameraPreviewView.swift
  DetectionModule/RectangleDetector.swift
  DetectionModule/QuadOverlayView.swift
  ProcessingModule/PerspectiveCorrector.swift
  ProcessingModule/AdjustmentPipeline.swift
  GalleryModule/GalleryItem.swift
  GalleryModule/GalleryStore.swift
  GalleryModule/GalleryView.swift
  ExportModule/ExportController.swift
  UI/DesignSystem.swift
  UI/EditView.swift
  UI/ScanView.swift
  UI/ContentView.swift
]

def uuid
  chars = ('A'..'F').to_a + ('0'..'9').to_a
  24.times.map { chars.sample }.join
end

# Generate UUIDs
MAIN_GROUP_UUID        = uuid
SOURCES_GROUP_UUID     = uuid
CAMERA_GROUP_UUID      = uuid
DETECTION_GROUP_UUID   = uuid
PROCESSING_GROUP_UUID  = uuid
GALLERY_GROUP_UUID     = uuid
EXPORT_GROUP_UUID      = uuid
UI_GROUP_UUID          = uuid
PRODUCTS_GROUP_UUID    = uuid
PROJECT_UUID           = uuid
TARGET_UUID            = uuid
BUILD_CONFIG_LIST_UUID = uuid
DEBUG_CONFIG_UUID      = uuid
RELEASE_CONFIG_UUID    = uuid
TARGET_CONFIG_LIST_UUID= uuid
TARGET_DEBUG_UUID      = uuid
TARGET_RELEASE_UUID    = uuid
SOURCES_PHASE_UUID     = uuid
FRAMEWORKS_PHASE_UUID  = uuid
RESOURCES_PHASE_UUID   = uuid
PRODUCT_REF_UUID       = uuid
INFO_PLIST_UUID        = uuid
ENTITLEMENTS_UUID      = uuid

# Map each source file to UUIDs (file ref + build file)
source_uuids = SOURCES.map { |s| [s, uuid, uuid] }
info_uuid = uuid
info_build_uuid = uuid

# Group membership
group_map = {
  CAMERA_GROUP_UUID    => SOURCES.select { |s| s.start_with?('CameraModule/') },
  DETECTION_GROUP_UUID => SOURCES.select { |s| s.start_with?('DetectionModule/') },
  PROCESSING_GROUP_UUID=> SOURCES.select { |s| s.start_with?('ProcessingModule/') },
  GALLERY_GROUP_UUID   => SOURCES.select { |s| s.start_with?('GalleryModule/') },
  EXPORT_GROUP_UUID    => SOURCES.select { |s| s.start_with?('ExportModule/') },
  UI_GROUP_UUID        => SOURCES.select { |s| s.start_with?('UI/') },
}
root_sources = SOURCES.reject { |s| s.include?('/') }

file_ref_uuid = source_uuids.map { |s, fref, bfile| [s, fref] }.to_h
build_file_uuid = source_uuids.map { |s, fref, bfile| [s, bfile] }.to_h

pbx = <<~PBXPROJ
  // !$*UTF8*$!
  {
  	archiveVersion = 1;
  	classes = {
  	};
  	objectVersion = 56;
  	objects = {

  /* Begin PBXBuildFile section */
PBXPROJ

source_uuids.each do |src, fref, bfile|
  name = File.basename(src)
  pbx += "\t\t#{bfile} /* #{name} in Sources */ = {isa = PBXBuildFile; fileRef = #{fref} /* #{name} */; };\n"
end
pbx += "\t\t#{info_build_uuid} /* Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = #{info_uuid} /* Info.plist */; };\n"

pbx += "/* End PBXBuildFile section */\n\n"

pbx += "/* Begin PBXFileReference section */\n"
source_uuids.each do |src, fref, bfile|
  name = File.basename(src)
  pbx += "\t\t#{fref} /* #{name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{name}; sourceTree = \"<group>\"; };\n"
end
pbx += "\t\t#{info_uuid} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };\n"
pbx += "\t\t#{PRODUCT_REF_UUID} /* PhotoTake.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PhotoTake.app; sourceTree = BUILT_PRODUCTS_DIR; };\n"
pbx += "/* End PBXFileReference section */\n\n"

pbx += "/* Begin PBXFrameworksBuildPhase section */\n"
pbx += "\t\t#{FRAMEWORKS_PHASE_UUID} /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
pbx += "/* End PBXFrameworksBuildPhase section */\n\n"

pbx += "/* Begin PBXGroup section */\n"

# Sub-groups
{
  CAMERA_GROUP_UUID => ['CameraModule', 'CameraModule/'],
  DETECTION_GROUP_UUID => ['DetectionModule', 'DetectionModule/'],
  PROCESSING_GROUP_UUID => ['ProcessingModule', 'ProcessingModule/'],
  GALLERY_GROUP_UUID => ['GalleryModule', 'GalleryModule/'],
  EXPORT_GROUP_UUID => ['ExportModule', 'ExportModule/'],
  UI_GROUP_UUID => ['UI', 'UI/'],
}.each do |g_uuid, (name, prefix)|
  members = SOURCES.select { |s| s.start_with?(prefix) }
  children = members.map { |s| "\t\t\t\t#{file_ref_uuid[s]} /* #{File.basename(s)} */," }.join("\n")
  pbx += "\t\t#{g_uuid} /* #{name} */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n#{children}\n\t\t\t);\n\t\t\tname = #{name};\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
end

# Main source group (PhotoTake)
main_children = root_sources.map { |s| "\t\t\t\t#{file_ref_uuid[s]} /* #{s} */," }
main_children += [
  "\t\t\t\t#{CAMERA_GROUP_UUID} /* CameraModule */,",
  "\t\t\t\t#{DETECTION_GROUP_UUID} /* DetectionModule */,",
  "\t\t\t\t#{PROCESSING_GROUP_UUID} /* ProcessingModule */,",
  "\t\t\t\t#{GALLERY_GROUP_UUID} /* GalleryModule */,",
  "\t\t\t\t#{EXPORT_GROUP_UUID} /* ExportModule */,",
  "\t\t\t\t#{UI_GROUP_UUID} /* UI */,",
  "\t\t\t\t#{info_uuid} /* Info.plist */,",
]

pbx += "\t\t#{SOURCES_GROUP_UUID} /* PhotoTake */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n#{main_children.join("\n")}\n\t\t\t);\n\t\t\tpath = PhotoTake;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"

# Products group
pbx += "\t\t#{PRODUCTS_GROUP_UUID} /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t#{PRODUCT_REF_UUID} /* PhotoTake.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"

# Main group
pbx += "\t\t#{MAIN_GROUP_UUID} = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t#{SOURCES_GROUP_UUID} /* PhotoTake */,\n\t\t\t\t#{PRODUCTS_GROUP_UUID} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"

pbx += "/* End PBXGroup section */\n\n"

pbx += "/* Begin PBXNativeTarget section */\n"
pbx += "\t\t#{TARGET_UUID} /* PhotoTake */ = {\n"
pbx += "\t\t\tisa = PBXNativeTarget;\n"
pbx += "\t\t\tbuildConfigurationList = #{TARGET_CONFIG_LIST_UUID};\n"
pbx += "\t\t\tbuildPhases = (\n\t\t\t\t#{SOURCES_PHASE_UUID} /* Sources */,\n\t\t\t\t#{FRAMEWORKS_PHASE_UUID} /* Frameworks */,\n\t\t\t\t#{RESOURCES_PHASE_UUID} /* Resources */,\n\t\t\t);\n"
pbx += "\t\t\tbuildRules = (\n\t\t\t);\n"
pbx += "\t\t\tdependencies = (\n\t\t\t);\n"
pbx += "\t\t\tname = PhotoTake;\n"
pbx += "\t\t\tproductName = PhotoTake;\n"
pbx += "\t\t\tproductReference = #{PRODUCT_REF_UUID};\n"
pbx += "\t\t\tproductType = \"com.apple.product-type.application\";\n"
pbx += "\t\t};\n"
pbx += "/* End PBXNativeTarget section */\n\n"

pbx += "/* Begin PBXProject section */\n"
pbx += "\t\t#{PROJECT_UUID} /* Project object */ = {\n"
pbx += "\t\t\tisa = PBXProject;\n"
pbx += "\t\t\tattributes = {\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1540;\n\t\t\t\tLastUpgradeCheck = 1540;\n\t\t\t\tTargetAttributes = {\n\t\t\t\t\t#{TARGET_UUID} = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.4;\n\t\t\t\t\t};\n\t\t\t\t};\n\t\t\t};\n"
pbx += "\t\t\tbuildConfigurationList = #{BUILD_CONFIG_LIST_UUID};\n"
pbx += "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
pbx += "\t\t\tdevelopmentRegion = en;\n"
pbx += "\t\t\thasScannedForEncodings = 0;\n"
pbx += "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
pbx += "\t\t\tmainGroup = #{MAIN_GROUP_UUID};\n"
pbx += "\t\t\tproductRefGroup = #{PRODUCTS_GROUP_UUID};\n"
pbx += "\t\t\tprojectDirPath = \"\";\n"
pbx += "\t\t\tprojectRoot = \"\";\n"
pbx += "\t\t\ttargets = (\n\t\t\t\t#{TARGET_UUID} /* PhotoTake */,\n\t\t\t);\n"
pbx += "\t\t};\n"
pbx += "/* End PBXProject section */\n\n"

pbx += "/* Begin PBXResourcesBuildPhase section */\n"
pbx += "\t\t#{RESOURCES_PHASE_UUID} /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
pbx += "/* End PBXResourcesBuildPhase section */\n\n"

pbx += "/* Begin PBXSourcesBuildPhase section */\n"
pbx += "\t\t#{SOURCES_PHASE_UUID} /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
source_uuids.each do |src, fref, bfile|
  name = File.basename(src)
  pbx += "\t\t\t\t#{bfile} /* #{name} in Sources */,\n"
end
pbx += "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
pbx += "/* End PBXSourcesBuildPhase section */\n\n"

build_settings_common = <<~SETTINGS
  				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
  				CODE_SIGN_STYLE = Automatic;
  				CURRENT_PROJECT_VERSION = 1;
  				DEVELOPMENT_TEAM = "";
  				GENERATE_INFOPLIST_FILE = NO;
  				INFOPLIST_FILE = PhotoTake/Info.plist;
  				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
  				MARKETING_VERSION = 1.0;
  				PRODUCT_BUNDLE_IDENTIFIER = com.soymachine.PhotoTake;
  				PRODUCT_NAME = PhotoTake;
  				SWIFT_EMIT_LOC_STRINGS = YES;
  				SWIFT_VERSION = 5.0;
  				TARGETED_DEVICE_FAMILY = 1;
SETTINGS

pbx += "/* Begin XCBuildConfiguration section */\n"

# Project configs
pbx += "\t\t#{DEBUG_CONFIG_UUID} /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
pbx += "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n"
pbx += "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
pbx += "\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;\n"
pbx += "\t\t\t\tCOPY_PHASE_STRIP = NO;\n"
pbx += "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n"
pbx += "\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;\n"
pbx += "\t\t\t\tENABLE_TESTABILITY = YES;\n"
pbx += "\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;\n"
pbx += "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n"
pbx += "\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n\t\t\t\t\t\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t);\n"
pbx += "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
pbx += "\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;\n"
pbx += "\t\t\t\tMTL_FAST_MATH = YES;\n"
pbx += "\t\t\t\tONLY_ACTIVE_ARCH = YES;\n"
pbx += "\t\t\t\tSDKROOT = iphoneos;\n"
pbx += "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n"
pbx += "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
pbx += "\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n"

pbx += "\t\t#{RELEASE_CONFIG_UUID} /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
pbx += "\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;\n"
pbx += "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
pbx += "\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;\n"
pbx += "\t\t\t\tCOPY_PHASE_STRIP = NO;\n"
pbx += "\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n"
pbx += "\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n"
pbx += "\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;\n"
pbx += "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n"
pbx += "\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;\n"
pbx += "\t\t\t\tMTL_FAST_MATH = YES;\n"
pbx += "\t\t\t\tSDKROOT = iphoneos;\n"
pbx += "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
pbx += "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n"
pbx += "\t\t\t\tVALIDATE_PRODUCT = YES;\n"
pbx += "\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"

# Target configs
pbx += "\t\t#{TARGET_DEBUG_UUID} /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n#{build_settings_common}\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n"
pbx += "\t\t#{TARGET_RELEASE_UUID} /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n#{build_settings_common}\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"

pbx += "/* End XCBuildConfiguration section */\n\n"

pbx += "/* Begin XCConfigurationList section */\n"
pbx += "\t\t#{BUILD_CONFIG_LIST_UUID} /* Build configuration list for PBXProject \"PhotoTake\" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t#{DEBUG_CONFIG_UUID} /* Debug */,\n\t\t\t\t#{RELEASE_CONFIG_UUID} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
pbx += "\t\t#{TARGET_CONFIG_LIST_UUID} /* Build configuration list for PBXNativeTarget \"PhotoTake\" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t#{TARGET_DEBUG_UUID} /* Debug */,\n\t\t\t\t#{TARGET_RELEASE_UUID} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
pbx += "/* End XCConfigurationList section */\n"

pbx += "\t};\n\trootObject = #{PROJECT_UUID} /* Project object */;\n}\n"

File.write(File.join(XCODEPROJ_DIR, 'project.pbxproj'), pbx)
puts "Generated #{XCODEPROJ_DIR}/project.pbxproj"
