import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
BROWSER_INSTALLER = REPO / "archiso/airootfs/usr/local/bin/frog-install-browser.sh"


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


class ContinuousIntegrationTests(unittest.TestCase):
    def test_ci_runs_repository_tests_and_live_boot_smoke_test(self):
        workflow = (REPO / ".github/workflows/build.yml").read_text()

        self.assertIn("python3 -m unittest discover -s tests -v", workflow)
        self.assertIn("bash scripts/smoke-test-iso.sh", workflow)


if __name__ == "__main__":
    unittest.main()
