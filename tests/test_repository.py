import json
import os
import shlex
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
BROWSER_INSTALLER = REPO / "archiso/airootfs/usr/local/bin/frog-install-browser.sh"
CALAMARES_MODULES = REPO / "archiso/airootfs/etc/calamares/modules"
SMOKE_TEST = REPO / "scripts/smoke-test-iso.sh"
BUILD_SCRIPT = REPO / "scripts/build-in-container.sh"


class PackageProfileTests(unittest.TestCase):
    def test_generic_image_does_not_force_nvidia_driver(self):
        packages = set(
            line.strip()
            for line in (REPO / "archiso/packages.x86_64").read_text().splitlines()
            if line.strip() and not line.startswith("#")
        )

        self.assertIn("xf86-video-nouveau", packages)
        self.assertNotIn("nvidia-open-dkms", packages)
        self.assertNotIn("nvidia-utils", packages)
        self.assertNotIn("nvidia-settings", packages)


class BrandingImageTests(unittest.TestCase):
    def test_calamares_uses_correctly_sized_branding_images(self):
        branding_dir = REPO / "archiso/airootfs/etc/calamares/branding/frog"
        branding = (branding_dir / "branding.desc").read_text()

        def png_size(name):
            data = (branding_dir / name).read_bytes()
            self.assertEqual(b"\x89PNG\r\n\x1a\n", data[:8])
            return struct.unpack(">II", data[16:24])

        self.assertIn('productIcon:         "icon.png"', branding)
        self.assertIn('productLogo:         "logo.png"', branding)
        self.assertIn('productWelcome:      "welcome.png"', branding)
        self.assertEqual((512, 512), png_size("icon.png"))
        self.assertEqual((512, 512), png_size("logo.png"))
        self.assertEqual((640, 300), png_size("welcome.png"))


class FetchConfigurationTests(unittest.TestCase):
    def test_fastfetch_and_fetch_use_the_frog_logo(self):
        logo_path = REPO / "archiso/airootfs/etc/skel/.config/fastfetch/logo.txt"
        config_path = REPO / "archiso/airootfs/etc/skel/.config/fastfetch/config.jsonc"
        init = (REPO / "archiso/airootfs/usr/local/bin/frog-init.sh").read_text()
        expected_logo = "\n".join(
            [
                "     ,.-----..__,.----.",
                "   ,´__                \\",
                "  / /  \\          ,--.  |",
                " |  `\"\"´_..-.___  \\__/  |",
                "(_\\                     \\",
                " (__,.---'\"´`\"'--.__ _, _)",
                "                    ``-.J",
            ]
        ) + "\n"

        config = json.loads(config_path.read_text())
        self.assertEqual(expected_logo, logo_path.read_text())
        self.assertEqual("file-raw", config["logo"]["type"])
        self.assertEqual("~/.config/fastfetch/logo.txt", config["logo"]["source"])
        self.assertIn("alias fetch='fastfetch'", init)
        self.assertIn("alias neofetch='fastfetch'", init)


class BrowserInstallerTests(unittest.TestCase):
    def run_installer(self, package, install_fails=False):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            fake_bin = temp / "bin"
            fake_bin.mkdir()
            log = temp / "pacman.log"
            pacman = fake_bin / "pacman"
            pacman.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$PACMAN_LOG\"\n"
                "if [[ \"$*\" == -Syu* && \"${PACMAN_INSTALL_FAIL:-0}\" == 1 ]]; then\n"
                "  exit 1\n"
                "fi\n"
            )
            pacman.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["PACMAN_LOG"] = str(log)
            env["PACMAN_INSTALL_FAIL"] = "1" if install_fails else "0"
            result = subprocess.run(
                ["bash", str(BROWSER_INSTALLER), package],
                env=env,
                text=True,
                capture_output=True,
            )
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls

    def test_removes_firefox_after_browser_install_succeeds(self):
        result, calls = self.run_installer("brave-bin")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            [
                "-Syu --noconfirm --needed brave-bin",
                "-Rns --noconfirm firefox",
            ],
            calls,
        )

    def test_keeps_firefox_when_browser_install_fails(self):
        result, calls = self.run_installer("zen-browser-bin", install_fails=True)

        self.assertNotEqual(0, result.returncode)
        self.assertEqual(["-Syu --noconfirm --needed zen-browser-bin"], calls)

    def test_rejects_packages_outside_the_browser_allowlist(self):
        result, calls = self.run_installer("untrusted-package")

        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], calls)

    def test_brave_origin_is_available_and_installable(self):
        chooser = (CALAMARES_MODULES / "packagechooser_browser.conf").read_text()
        installer = (CALAMARES_MODULES / "contextualprocess_browser.conf").read_text()
        result, calls = self.run_installer("brave-origin-bin")

        self.assertIn("  - id: brave-origin", chooser)
        self.assertIn("    package: brave-origin-bin", chooser)
        self.assertIn("    name: Brave Origin", chooser)
        self.assertIn("    brave-origin:", installer)
        self.assertIn("frog-install-browser.sh brave-origin-bin", installer)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            [
                "-Syu --noconfirm --needed brave-origin-bin",
                "-Rns --noconfirm firefox",
            ],
            calls,
        )

    def test_helper_is_removed_only_after_browser_selection(self):
        cleanup = (
            REPO / "archiso/airootfs/usr/local/bin/frog-postinstall-cleanup.sh"
        ).read_text()
        settings = (REPO / "archiso/airootfs/etc/calamares/settings.conf").read_text()
        helper_cleanup = (
            REPO
            / "archiso/airootfs/etc/calamares/modules/shellprocess_remove_browser_helper.conf"
        ).read_text()

        self.assertNotIn("frog-install-browser.sh", cleanup)
        browser_index = settings.index("  - contextualprocess@browser-install")
        cleanup_index = settings.index("  - shellprocess@remove-browser-helper")
        initcpio_index = settings.index("  - initcpio")
        self.assertLess(browser_index, cleanup_index)
        self.assertLess(cleanup_index, initcpio_index)
        self.assertIn("rm -f /usr/local/bin/frog-install-browser.sh", helper_cleanup)


class LiveUserCleanupTests(unittest.TestCase):
    def test_live_session_logs_back_in_after_session_exit(self):
        autologin = (
            REPO / "archiso/airootfs/etc/sddm.conf.d/autologin.conf"
        ).read_text()

        self.assertIn("User=liveuser", autologin)
        self.assertIn("Session=plasma.desktop", autologin)
        self.assertIn("Relogin=true", autologin)

    def test_cleanup_revokes_liveuser_credentials_before_removal(self):
        cleanup = (
            REPO / "archiso/airootfs/usr/local/bin/frog-postinstall-cleanup.sh"
        ).read_text()

        self.assertIn("usermod --lock liveuser", cleanup)
        self.assertIn("gpasswd --delete liveuser wheel", cleanup)

    def test_install_fails_if_removeuser_leaves_the_account_behind(self):
        settings = (REPO / "archiso/airootfs/etc/calamares/settings.conf").read_text()
        verification = (
            REPO
            / "archiso/airootfs/etc/calamares/modules/shellprocess_verify_liveuser.conf"
        ).read_text()

        remove_index = settings.index("  - removeuser")
        verify_index = settings.index("  - shellprocess@verify-liveuser")
        umount_index = settings.index("  - umount")
        self.assertLess(remove_index, verify_index)
        self.assertLess(verify_index, umount_index)
        self.assertIn("getent passwd liveuser", verification)
        self.assertNotIn('command: "-', verification)


class UnpackfsConfigurationTests(unittest.TestCase):
    def test_uses_mounted_airootfs_when_boot_medium_is_unmounted(self):
        unpackfs = (CALAMARES_MODULES / "unpackfs.conf").read_text()

        self.assertIn('source: "/run/archiso/airootfs"', unpackfs)
        self.assertIn('sourcefs: "file"', unpackfs)
        self.assertNotIn('source: "/run/archiso/bootmnt', unpackfs)


class CalamaresStartupTests(unittest.TestCase):
    def test_welcome_requirements_avoid_crashing_hardware_probes(self):
        welcome = (CALAMARES_MODULES / "welcome.conf").read_text()

        self.assertNotIn("- power", welcome)
        self.assertNotIn("- storage", welcome)
        self.assertIn("- ram", welcome)
        self.assertIn("- root", welcome)
        self.assertIn("- screen", welcome)

    def test_required_application_settings_are_explicit(self):
        settings = (REPO / "archiso/airootfs/etc/calamares/settings.conf").read_text()

        self.assertIn("oem-setup: false", settings)
        self.assertIn("disable-cancel: false", settings)
        self.assertIn("disable-cancel-during-exec: false", settings)
        self.assertIn("hide-back-and-next-during-exec: false", settings)
        self.assertIn("quit-at-end: false", settings)


class LiveOverlayTests(unittest.TestCase):
    def test_boot_entries_use_a_two_gibibyte_writable_overlay(self):
        build_script = BUILD_SCRIPT.read_text()
        smoke_test = SMOKE_TEST.read_text()

        self.assertIn("cow_spacesize=2G", build_script)
        self.assertIn("cow_spacesize=2G", smoke_test)


class ContinuousIntegrationTests(unittest.TestCase):
    def test_ci_runs_repository_tests_and_live_boot_smoke_test(self):
        workflow = (REPO / ".github/workflows/build.yml").read_text()

        self.assertIn("python3 -m unittest discover -s tests -v", workflow)
        self.assertIn("bash scripts/smoke-test-iso.sh", workflow)


class SmokeTestScriptTests(unittest.TestCase):
    def run_bash(self, command):
        return subprocess.run(
            ["bash", "-c", f"source {shlex.quote(str(SMOKE_TEST))}; {command}"],
            text=True,
            capture_output=True,
        )

    def test_strips_systemd_ansi_codes_before_matching_sddm(self):
        result = self.run_bash(
            "printf $'[\\e[0;32m  OK  \\e[0m] Started "
            "\\e[0;1;39mSimple Desktop Display Manager\\e[0m.\\n' | strip_ansi"
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "[  OK  ] Started Simple Desktop Display Manager.\n",
            result.stdout,
        )

    def test_cleanup_removes_read_only_extracted_directories(self):
        result = self.run_bash(
            'SMOKE_DIR="$(mktemp -d)"; QEMU_PID=""; '
            'mkdir -p "$SMOKE_DIR/iso-boot/syslinux"; '
            'touch "$SMOKE_DIR/iso-boot/syslinux/boot.cat"; '
            'chmod -R a-w "$SMOKE_DIR/iso-boot"; '
            'cleanup; test ! -e "$SMOKE_DIR"'
        )

        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
