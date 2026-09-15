"""Applies the demo layer to a throwaway copy of the Mood PlayStation app.

The app repository itself never contains demo code: this copies in
lib/demo/ and the branded web/ shell, then makes two small, asserted edits
so a source change upstream fails loudly instead of silently shipping a
demo without its data or with the real owner password.
"""
import pathlib
import shutil
import sys

overlay = pathlib.Path(__file__).resolve().parent
app = pathlib.Path(sys.argv[1])


def patch(relative, old, new):
    path = app / relative
    source = path.read_text()
    if source.count(old) != 1:
        sys.exit(f"overlay: expected exactly one match in {relative}:\n{old}")
    path.write_text(source.replace(old, new))


shutil.copytree(overlay / "lib" / "demo", app / "lib" / "demo", dirs_exist_ok=True)
shutil.rmtree(app / "web", ignore_errors=True)
shutil.copytree(overlay / "web", app / "web")

patch(
    "lib/main.dart",
    "  await HiveService.init();\n",
    "  await HiveService.init();\n"
    "  await DemoSeeder.seedIfNeeded();\n",
)
patch(
    "lib/main.dart",
    "import 'core/services/hive_service.dart';\n",
    "import 'core/services/hive_service.dart';\n"
    "import 'demo/demo_seeder.dart';\n",
)

shift = "lib/features/shift/screens/shift_summary_screen.dart"
patch(
    shift,
    "import '../../../core/utils/formatters.dart';\n",
    "import '../../../core/utils/formatters.dart';\n"
    "import '../../../demo/demo_mode.dart';\n",
)
patch(shift, "const _ownerPassword = 'Mood2023';", "const _ownerPassword = kDemoOwnerPassword;")
patch(
    shift,
    "              labelText: 'كلمة المرور',\n              errorText: error,\n",
    "              labelText: 'كلمة المرور',\n              errorText: error,\n"
    "              helperText: 'Demo password: $kDemoOwnerPassword',\n",
)
patch(
    shift,
    "                        labelText: 'كلمة المرور',\n                        errorText: _error,\n",
    "                        labelText: 'كلمة المرور',\n                        errorText: _error,\n"
    "                        helperText: 'Demo password: $kDemoOwnerPassword',\n",
)
print("overlay applied")
