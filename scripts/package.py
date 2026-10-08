#!/usr/bin/env python3
"""Build dist/<name>-<version>.vsix with the Python standard library only.

A .vsix is a zip holding [Content_Types].xml, extension.vsixmanifest and the
extension files under extension/. The official tool (`npx @vscode/vsce package`)
produces an equivalent package; this script just avoids the Node dependency.
"""
import json
import pathlib
import zipfile
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["package.json", "extension.js", "README.md", "CHANGELOG.md", "LICENSE"]

pkg = json.loads((ROOT / "package.json").read_text())
name, version, publisher = pkg["name"], pkg["version"], pkg["publisher"]
engine = pkg["engines"]["vscode"]
kind = ",".join(pkg.get("extensionKind", ["workspace"]))

content_types = (
    '<?xml version="1.0" encoding="utf-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension=".json" ContentType="application/json"/>'
    '<Default Extension=".js" ContentType="application/javascript"/>'
    '<Default Extension=".md" ContentType="text/markdown"/>'
    '<Default Extension=".vsixmanifest" ContentType="text/xml"/>'
    '<Default Extension="" ContentType="text/plain"/>'
    "</Types>"
)

manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{escape(name)}" Version="{escape(version)}" Publisher="{escape(publisher)}"/>
    <DisplayName>{escape(pkg.get("displayName", name))}</DisplayName>
    <Description xml:space="preserve">{escape(pkg.get("description", ""))}</Description>
    <Tags>{escape(",".join(pkg.get("keywords", [])))}</Tags>
    <Categories>{escape(",".join(pkg.get("categories", ["Other"])))}</Categories>
    <License>extension/LICENSE</License>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{escape(engine)}"/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="{escape(kind)}"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
    <Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true"/>
    <Asset Type="Microsoft.VisualStudio.Services.Content.Changelog" Path="extension/CHANGELOG.md" Addressable="true"/>
    <Asset Type="Microsoft.VisualStudio.Services.Content.License" Path="extension/LICENSE" Addressable="true"/>
  </Assets>
</PackageManifest>
"""

out = ROOT / "dist" / f"{name}-{version}.vsix"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("extension.vsixmanifest", manifest)
    for f in FILES:
        z.write(ROOT / f, f"extension/{f}")
print(out.relative_to(ROOT))
