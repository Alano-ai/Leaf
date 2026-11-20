# App icon and installer

`render.swift` draws the app icon and Finder background at standard and Retina resolutions. The AppIcon asset catalog contains the rendered macOS sizes. `Installer.dmg` is a small, app-free HFS+ image containing the Finder layout, background and Applications shortcut. The packaging script copies the new app into a temporary writable image and preserves the background bookmark when compressing it for release. Normal local packaging and CI use Xcode and the system disk image utilities.

To revise the designs on macOS, regenerate the source images and the icon sizes from the repository root.

```sh
xcrun swift Design/render.swift build/installer-art
icon=Leaf/Assets.xcassets/AppIcon.appiconset
cp build/installer-art/LeafIcon.png "$icon/1024.png"
for size in 16 32 64 128 256 512; do
  sips -z "$size" "$size" "$icon/1024.png" --out "$icon/$size.png"
done
tiffutil -cathidpicheck build/installer-art/Installer.png build/installer-art/Installer@2x.png \
  -out build/installer-art/Installer.tiff
```

To regenerate the reusable disk image, use [dmgbuild](https://github.com/dmgbuild/dmgbuild) as an authoring tool. The generated image is the only output used by packaging.

```sh
python3 -m pip install --target build/installer-art/tools \
  'dmgbuild==1.6.5' 'ds_store==1.3.1' 'mac_alias==2.2.2'
PYTHONPATH="$PWD/build/installer-art/tools" python3 -m dmgbuild -s Design/installer-layout.py \
  -D background=build/installer-art/Installer.tiff 'Install Leaf' build/installer-art/Installer.dmg
cp build/installer-art/Installer.dmg Design/Installer.dmg
```

Package a test DMG and open it from Finder to check the arrow, app icon, shortcut and installation instructions together.
