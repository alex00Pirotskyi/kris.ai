# Actual write/sort/snapshot regressions for canonical repository-relative paths.


def _windows_short_path(path: Path) -> Path | None:
    if os.name != "nt":
        return None
    import ctypes
    from ctypes import wintypes

    get_short = ctypes.windll.kernel32.GetShortPathNameW
    get_short.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
    get_short.restype = wintypes.DWORD
    buffer = ctypes.create_unicode_buffer(32768)
    length = get_short(str(path), buffer, len(buffer))
    if not length or length >= len(buffer):
        return None
    result = Path(buffer.value)
    if os.path.normcase(str(result)) == os.path.normcase(str(path)):
        return None
    return result


class AnarchyControlPlaneRepositoryRelativeRuntimeTest(unittest.TestCase):
    def test_fixture_construction_write_generated_accepts_lexical_root_alias(self) -> None:
        """Reproduce fixture creation -> write_generated -> generated path identity."""
        with repository() as root:
            alias_parent = root / "runtime-alias"
            alias_parent.mkdir()
            alias_root = alias_parent / ".."
            result = acp.write_generated(alias_root)
            self.assertEqual(
                result["path"],
                "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json",
            )
            self.assertFalse(result["changed"])

    @unittest.skipUnless(sys.platform == "darwin", "macOS /var alias regression")
    def test_write_generated_accepts_var_private_var_alias(self) -> None:
        base = Path("/var/tmp")
        if not base.is_dir():
            self.skipTest("/var/tmp is unavailable")
        with tempfile.TemporaryDirectory(prefix="p24-write-var-", dir=base) as temporary:
            lexical_root = Path(temporary) / "repository"
            lexical_root.mkdir()
            self.assertNotEqual(str(lexical_root), str(lexical_root.resolve(strict=True)))
            build_repository(lexical_root)
            result = acp.write_generated(lexical_root)
            self.assertEqual(
                result["path"],
                "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json",
            )

    @unittest.skipUnless(os.name == "nt", "Windows 8.3 write regression")
    def test_write_generated_accepts_windows_short_root_alias(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24 windows write ") as temporary:
            long_root = Path(temporary) / "repository with spaces"
            long_root.mkdir()
            build_repository(long_root)
            short_root = _windows_short_path(long_root)
            if short_root is None:
                self.skipTest("8.3 aliases are unavailable on the runner volume")
            result = acp.write_generated(short_root)
            self.assertEqual(
                result["path"],
                "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json",
            )

    @unittest.skipUnless(os.name == "nt", "Windows case-alias write regression")
    def test_write_generated_accepts_windows_case_alias(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-case-write-") as temporary:
            root = Path(temporary) / "RepositoryCase"
            root.mkdir()
            build_repository(root)
            case_alias = root.with_name(root.name.swapcase())
            result = acp.write_generated(case_alias)
            self.assertEqual(
                result["path"],
                "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json",
            )

    def test_repository_relative_returns_stable_posix_text(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-posix-") as temporary:
            root = Path(temporary) / "repository"
            target = root / "nested" / "deeper" / "file.json"
            target.parent.mkdir(parents=True)
            target.write_text("{}\n", encoding="utf-8", newline="\n")
            relative = acp.repository_relative(root, target, must_exist=True)
            self.assertEqual(relative, "nested/deeper/file.json")
            self.assertNotIn("\\", relative)

    def test_snapshot_scopes_is_alias_invariant(self) -> None:
        with repository() as root:
            alias_parent = root / "snapshot-alias"
            alias_parent.mkdir()
            alias_root = alias_parent / ".."
            scopes = ["docs/roadmap/anarchy", "tool/anarchy_control_plane_parts"]
            self.assertEqual(
                acp.snapshot_scopes(root, scopes),
                acp.snapshot_scopes(alias_root, scopes),
            )

    def test_iter_scope_files_sorting_is_alias_invariant(self) -> None:
        with repository() as root:
            alias_parent = root / "sort-alias"
            alias_parent.mkdir()
            alias_root = alias_parent / ".."
            canonical = [
                acp.repository_relative(root, path, must_exist=True)
                for path in acp.iter_scope_files(root, "docs/roadmap/anarchy/workers")
            ]
            aliased = [
                acp.repository_relative(alias_root, path, must_exist=True)
                for path in acp.iter_scope_files(alias_root, "docs/roadmap/anarchy/workers")
            ]
            self.assertEqual(aliased, canonical)
            self.assertEqual(canonical, sorted(canonical))

    def test_repository_relative_root_equality_is_explicit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-root-") as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            self.assertEqual(acp.repository_relative(root, root, must_exist=True), ".")

    def test_repository_relative_accepts_nonexistent_in_root_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-output-") as temporary:
            root = Path(temporary) / "repository"
            parent = root / "generated"
            parent.mkdir(parents=True)
            candidate = parent / "future.json"
            self.assertEqual(
                acp.repository_relative(root, candidate, must_exist=False),
                "generated/future.json",
            )

    def test_repository_relative_missing_required_input_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-missing-") as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            with self.assertRaises(acp.ControlPlaneError):
                acp.repository_relative(root, root / "missing.json", must_exist=True)

    def test_repository_relative_rejects_traversal_and_sibling_prefix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-escape-") as temporary:
            root = Path(temporary) / "repo"
            sibling = Path(temporary) / "repo-sibling"
            root.mkdir()
            sibling.mkdir()
            outside = Path(temporary) / "outside.txt"
            outside.write_text("outside\n", encoding="utf-8", newline="\n")
            with self.assertRaises(acp.ControlPlaneError):
                acp.resolve_safe(root, "../outside.txt", must_exist=True)
            with self.assertRaises(acp.ControlPlaneError):
                acp.repository_relative(root, sibling, must_exist=True)

    def test_repository_relative_rejects_symlink_escape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-link-") as temporary:
            root = Path(temporary) / "repository"
            outside = Path(temporary) / "outside"
            root.mkdir()
            outside.mkdir()
            secret = outside / "secret.txt"
            secret.write_text("secret\n", encoding="utf-8", newline="\n")
            link = root / "escape"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            with self.assertRaises(acp.ControlPlaneError):
                acp.repository_relative(root, link / "secret.txt", must_exist=True)

    def test_repository_relative_in_root_symlink_uses_canonical_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-relative-in-link-") as temporary:
            root = Path(temporary) / "repository"
            target = root / "target"
            target.mkdir(parents=True)
            file_path = target / "file.txt"
            file_path.write_text("inside\n", encoding="utf-8", newline="\n")
            link = root / "alias"
            try:
                link.symlink_to(target, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink creation unavailable: {error}")
            self.assertEqual(
                acp.repository_relative(root, link / "file.txt", must_exist=True),
                "target/file.txt",
            )

    @unittest.skipUnless(os.name == "nt", "Windows junction escape regression")
    def test_repository_relative_rejects_windows_junction_escape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-junction-") as temporary:
            root = Path(temporary) / "repository"
            outside = Path(temporary) / "outside"
            root.mkdir()
            outside.mkdir()
            secret = outside / "secret.txt"
            secret.write_text("secret\n", encoding="utf-8", newline="\n")
            junction = root / "escape"
            created = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(junction), str(outside)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            if created.returncode != 0:
                self.skipTest(f"junction creation unavailable: {created.stdout}")
            with self.assertRaises(acp.ControlPlaneError):
                acp.repository_relative(root, junction / "secret.txt", must_exist=True)

    @unittest.skipUnless(os.name == "nt", "Windows cross-drive regression")
    def test_repository_relative_rejects_windows_cross_drive(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-cross-drive-") as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            other_root = None
            for letter in "CDEFGHIJKLMNOPQRSTUVWXYZ":
                candidate = Path(f"{letter}:\\")
                if candidate.exists() and candidate.drive.lower() != root.drive.lower():
                    other_root = candidate
                    break
            if other_root is None:
                self.skipTest("no second mounted drive is available")
            with self.assertRaises(acp.ControlPlaneError):
                acp.repository_relative(root, other_root, must_exist=True)
