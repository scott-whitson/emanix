import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import md2org


class TestSlugify(unittest.TestCase):
    def test_spaces(self):
        self.assertEqual(md2org.slugify("The Paper Corp"), "the_paper_corp")

    def test_punctuation(self):
        self.assertEqual(md2org.slugify("Rubber, Inc."), "rubber_inc")

    def test_empty(self):
        self.assertEqual(md2org.slugify("!!!"), "untitled")


class TestTargetName(unittest.TestCase):
    def test_mtime_and_collision_bump(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "Note.md"
            p.write_text("x")
            os.utime(p, (1718200530, 1718200530))  # fixed mtime
            used = set()
            first = md2org.target_name(p, used)
            second = md2org.target_name(p, used)  # same file again -> +1s bump
            self.assertRegex(first, r"^\d{14}-note\.org$")
            self.assertNotEqual(first, second)
            self.assertEqual(len(used), 2)


class TestFrontmatter(unittest.TestCase):
    def test_split_and_keys(self):
        text = "---\ntitle: Real Title\ntags: [alpha, beta]\nauthor: scott\n---\nBody here\n"
        meta, body, dropped = md2org.split_frontmatter(text)
        self.assertEqual(meta["title"], "Real Title")
        self.assertEqual(meta["tags"], ["alpha", "beta"])
        self.assertEqual(dropped, ["author"])
        self.assertEqual(body, "Body here\n")

    def test_no_frontmatter(self):
        meta, body, dropped = md2org.split_frontmatter("Just body\n")
        self.assertEqual(meta, {})
        self.assertEqual(body, "Just body\n")
        self.assertEqual(dropped, [])


class TestWikilinks(unittest.TestCase):
    def setUp(self):
        # resolver: name(lower) -> uuid, only 'central data' resolves
        self.resolve = lambda name: (
            "UUID-CD" if name.lower() == "central data" else None
        )

    def roundtrip(self, text):
        protected, tokens = md2org.protect(text)
        self.assertNotIn("[[", protected)
        log = []
        return md2org.restore(protected, tokens, self.resolve, log), log

    def test_resolved(self):
        out, _ = self.roundtrip("see [[Central Data]] now")
        self.assertEqual(out, "see [[id:UUID-CD][Central Data]] now")

    def test_alias(self):
        out, _ = self.roundtrip("see [[Central Data|CD]] now")
        self.assertEqual(out, "see [[id:UUID-CD][CD]] now")

    def test_anchor_dropped_and_logged(self):
        out, log = self.roundtrip("see [[Central Data#Billing]] now")
        self.assertEqual(out, "see [[id:UUID-CD][Central Data]] now")
        self.assertTrue(any("anchor" in line for line in log))

    def test_unresolved(self):
        out, _ = self.roundtrip("see [[Ghost Note]] now")
        self.assertEqual(out, "see [[roam:Ghost Note]] now")

    def test_image_embed(self):
        out, _ = self.roundtrip("![[Pasted image 1.png]]")
        self.assertEqual(out, "[[file:Pasted image 1.png]]")

    def test_embed_anchor_logged(self):
        out, log = self.roundtrip("![[Doc.pdf#page=2]]")
        self.assertEqual(out, "[[file:Doc.pdf]]")
        self.assertTrue(any("anchor" in line for line in log))


class TestHeader(unittest.TestCase):
    def test_header_and_filetags(self):
        h = md2org.org_header("U1", "My Note", ["alpha", "beta"])
        self.assertIn(":ID:       U1", h)
        self.assertIn("#+title: My Note", h)
        self.assertIn("#+filetags: :alpha:beta:", h)

    def test_drop_dup_heading(self):
        body = "* The Paper Corp\n\nContent\n"
        self.assertEqual(
            md2org.drop_dup_heading(body, "The Paper Corp"), "\nContent\n"
        )
        self.assertEqual(
            md2org.drop_dup_heading(body, "Other"), body
        )


@unittest.skipUnless(shutil.which("pandoc"), "pandoc not on PATH")
class TestEndToEnd(unittest.TestCase):
    def test_convert_vault(self):
        with tempfile.TemporaryDirectory() as d:
            vault = Path(d)
            (vault / "Central Data.md").write_text("# Central Data\n\nHub note.\n")
            (vault / "Client.md").write_text(
                "---\ntitle: Client X\nauthor: s\n---\n"
                "Linked to [[Central Data]] and [[Missing]].\n\n"
                "| a | b |\n|---|---|\n| 1 | 2 |\n"
            )
            (vault / "Templates").mkdir()
            (vault / "Templates" / "T.md").write_text("[[skip me]]")
            run = lambda *a: subprocess.run(
                ["python3", str(Path(__file__).parent / "md2org.py"), *a,
                 "--vault", str(vault)],
                capture_output=True, text=True)
            r = run("map")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(
                len((vault / ".conversion-map.tsv").read_text().splitlines()), 2)
            r = run("convert")
            self.assertEqual(r.returncode, 0, r.stderr)
            orgs = sorted(vault.glob("*.org"))
            self.assertEqual(len(orgs), 2)
            client = next(p for p in orgs if "client" in p.name).read_text()
            self.assertIn("#+title: Client X", client)     # frontmatter title wins
            self.assertIn("[[id:", client)                  # resolved link
            self.assertIn("[[roam:Missing]]", client)       # dangling link
            self.assertIn("|", client)                      # table survived
            self.assertNotIn("Central Data.org", [p.name for p in orgs])  # roam-named
            # md untouched by convert; Templates skipped
            self.assertTrue((vault / "Client.md").exists())
            self.assertFalse(list((vault / "Templates").glob("*.org")))
            log = (vault / ".conversion-log.txt").read_text()
            self.assertIn("author", log)                    # dropped key logged

            # re-running convert must be idempotent: never overwrite, just skip
            before = client_org_path = next(p for p in orgs if "client" in p.name)
            before_content = before.read_text()
            r = run("convert")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("skipped", r.stdout)
            after_content = client_org_path.read_text()
            self.assertEqual(before_content, after_content)

            r = run("delete-md")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse((vault / "Client.md").exists())
            self.assertTrue((vault / "Templates" / "T.md").exists())  # never deleted


class TestPandocFailure(unittest.TestCase):
    def test_pandoc_failure_continues(self):
        with tempfile.TemporaryDirectory() as d:
            vault = Path(d)
            (vault / "Good.md").write_text("# Good\n\nGood body.\n")
            (vault / "Bad.md").write_text("# Bad\n\nBad body.\n")

            def fake_convert_body(body):
                if "Bad body" in body:
                    raise subprocess.CalledProcessError(1, "pandoc", stderr="boom")
                return "converted body\n"

            orig_convert_body = md2org.convert_body
            md2org.convert_body = fake_convert_body
            try:
                try:
                    md2org.cmd_convert(vault)
                    exit_code = 0
                except SystemExit as e:
                    exit_code = e.code
            finally:
                md2org.convert_body = orig_convert_body

            self.assertEqual(exit_code, 1)
            orgs = list(vault.glob("*.org"))
            self.assertEqual(len(orgs), 1)
            self.assertIn("good", orgs[0].name.lower())
            log = (vault / ".conversion-log.txt").read_text()
            self.assertIn("PANDOC-FAILED", log)


if __name__ == "__main__":
    unittest.main()
