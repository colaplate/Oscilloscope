#! /bin/bash

. scripts/functions.sh

platform=$1
version=$2
distDir="dist/Dyad-$version-$platform"

if [[ -z "$version" || -z "$platform" ]]
then
	echo "Usage: dist.sh <platform> <version>"
	echo ""
	echo "Platform: One of the following: "
	echo "          osx, linux, linux64, win32, win64" 
	echo "Version:  Anything you like"
	exit
fi


pushd `dirname $0`
cd ..

if [ -d "$distDir" ]
then
	echo "Cleaning out work folder first ..."
	rm -rf "$distDir"
fi


mkdir -p "$distDir"
cp -R bin/* "$distDir"

cp -R docs "$distDir"
mkdir -p "$distDir/docs/ffmpeg"
cp -R addons/ofxAvCodec/ffmpeg_src/readme.md "$distDir/docs/ffmpeg/notes.md"
cp -R addons/ofxAvCodec/libs/avcodec/LICENSE.md "$distDir/docs/ffmpeg/license.md"
cp -R addons/ofxAvCodec/libs/avcodec/README.md "$distDir/docs/ffmpeg/readme.md"
cp readme.md "$distDir"
rm "$distDir/DyadDebug.*"

echo "platform = $platform"

if [ "$platform" = "win32" ] || [ "$platform" = "win64" ]
then
	pushd
	cd "$distDir"
	dlls="assimp.dll Zlib.dll glut32.dll libeay32.dll ssleay32.dll swscale-4.dll Zlib.dll FreeType.dll fmodex64.dll fmodex64L.dll"
	echo "Deleting unused DLL files: $dlls "
	echo "Make sure they are specified as 'delay loaded DLLs' in the linker settings"
	rm $dlls
	rm DyadDebug.*
	
	popd
	
	if [ ! -x "$(command -v candle)" ]
	then
		echo "Adding wix toolset to path"
		export PATH="$PATH":"/c/Program Files (x86)/WiX Toolset v3.11/bin"
	fi
	
	echo "Creating Wix Archive"
	echo "  * Querying uuid for $version"
	code="$(getOrCreateWixCode "$version")"
	echo "    $code"

	echo "  * Building file list for heat..."
	heat dir "$distDir" -sreg -srd -ag -dr INSTALLDIR -cg CGROUP -t assets/wix_heat.xslt -out assets/wix_files.wxs 1>/dev/null

	echo "  * Preparing assets/wix_config.wxi ..."
	# in case you are some random person on the internet: 
	# 1. actually read the comments in the wix config, you'll have to make changes
	# 2. use uuidgen.exe to create your own numbers, don't reuse mine! 
	cat >assets/wix_config.wxi <<EOF
		<Include>
			<?define MyProductName = "Dyad" ?>
			<!-- use a random version+udid each run! -->
			<?define MyAppVersion = "$version" ?>
			<?define MyVersionId = "$code" ?>
			<?define MyManufacturer = "Hansi Raber" ?>
			<?define MyUninstallerIconPath = "assets/icon.ico" ?>
			<!-- for these: create random udid once, then use the same code each run! -->
			<?define MyConstantUpgradeCode = "29A20305-C6D5-43F6-B7D6-6F092B707EC8" ?>
			<?define MyProgramMenuGuid = "0CFFC475-3F05-4F84-BACF-E392566B95F5" ?>
			<!-- find these in the wix_files.wxs generated by heat -->
			<!-- run heat manually the first time! -->
			<!--   you can use "INSTALLDIR" for the main directory! -->
			<!--   or something like dirE346A75FEDD174A44A845475C6757E1F-->
			<?define MyExeWorkingDir = "INSTALLDIR" ?>
			<?define MyExeId="fil93A808E5891A09DC03421F6DA54303DF" ?>
		</Include>
EOF

	echo "  * Compiling sources (candle) ..."
	candle assets/wix_main.wxs assets/wix_files.wxs 1>/dev/null

	echo "  * Linking results (light) ..."
	installerTarget="dist/$(basename "$distDir").msi"
	light -ext WixUIExtension -cultures:en-us -b "$distDir" wix_files.wixobj wix_main.wixobj  -o "$installerTarget"
	
	echo "  * Cleaning up"
	rm *.wixobj
	rm dist/*.wixpdb
	
	echo "  * Creating portable zip"
	cd dist
	zipTarget="$(basename "$distDir").zip"
	zip -r "$zipTarget" "$(basename "$distDir")" 
	cd ..

elif [ "$platform" = "osx" ]
then
	echo "Moving data folder into resources"
	cd "$distDir"
	mv data/* Dyad.app/Contents/Resources
	rm -rf data
	
	echo "Stripping all dylibs to 64bit only"
	for file in $(find Dyad.app -type f -name "*.dylib")
	do
		echo "    > processing " $(basename $file)
		mv "$file" /tmp/dyad-fatlib.dylib
		lipo /tmp/dyad-fatlib.dylib -thin x86_64 -output "$file"
		rm /tmp/dyad-fatlib.dylib
	done
fi

popd

echo "----------------------------"
echo "Generated ${dest}"
echo `du -h "$distDir" | tail -n 1 | cut -f 1`
echo "----------------------------"
