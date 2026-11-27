# Installer translations

The setup wizard offers 78 language choices. It uses 34 message files bundled with Inno Setup 7.1.1 and 44 more from the upstream [translation directory](https://jrsoftware.org/inno-setup/translations), pinned to the [Inno Setup 7.1.1 source release](https://github.com/jrsoftware/issrc/tree/is-7_1_1/Files/Languages/Unofficial). Regional and script variants, such as Brazilian and European Portuguese or Serbian in Cyrillic and Latin, are separate choices.

Maintainer credits appear in the original files. The seven original `.islu` files use the `.isl` extension here. Some legacy files were converted to UTF-8 for compiler compatibility. Locale identifiers were corrected where they pointed to a different language or overlapped a separate choice. The Marathi display name and Latvian welcome heading were corrected. Modified files identify the changes in their headers. See the accompanying [Inno Setup license](LICENSE-Inno-Setup.txt).

Some recent installer messages and app-specific options use English when the chosen translation does not supply them. These files translate the installer wizard. Super Booster's in-app interface has its own text.
