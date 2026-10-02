#!/usr/bin/env python3
"""Build separate claude.ai upload ZIPs from skills installed by dotfiles."""

from __future__ import annotations

import argparse
import re
import shutil
import stat
import sys
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ALLOWED_FRONTMATTER = {
    "name",
    "description",
    "license",
    "compatibility",
    "metadata",
    "allowed-tools",
}
MANAGED_PREFIXES = ("pstack--", "impeccable--", "caveman--", "ponytail--", "dotfiles--")


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", value.lower()).strip("-")


def frontmatter_for_upload(text: str, skill_name: str) -> tuple[str, list[str]]:
    if not text.startswith("---\n"):
        raise ValueError("SKILL.md must begin with YAML frontmatter")
    end = text.find("\n---\n", 4)
    if end < 0:
        raise ValueError("SKILL.md has no closing frontmatter delimiter")

    source_lines = text[4:end].splitlines()
    blocks: list[tuple[str, list[str]]] = []
    dropped: list[str] = []
    i = 0
    while i < len(source_lines):
        line = source_lines[i]
        match = re.match(r"^([A-Za-z0-9_-]+):", line)
        if not match:
            i += 1
            continue
        key = match.group(1)
        block = [line]
        i += 1
        while i < len(source_lines) and (
            source_lines[i].startswith((" ", "\t")) or not source_lines[i]
        ):
            block.append(source_lines[i])
            i += 1
        if key in ALLOWED_FRONTMATTER:
            blocks.append((key, block))
        else:
            dropped.append(key)

    if not any(key == "description" for key, _ in blocks):
        raise ValueError("SKILL.md must include a description")
    if not re.fullmatch(r"[a-z0-9-]{1,64}", skill_name) or skill_name in {"claude", "anthropic"}:
        raise ValueError(f"unsupported Claude skill name: {skill_name}")

    output_lines: list[str] = []
    for key, block in blocks:
        if key == "name":
            output_lines.append(f"name: {skill_name}")
            output_lines.extend(block[1:])
        else:
            output_lines.extend(block)
    if not any(key == "name" for key, _ in blocks):
        output_lines.insert(0, f"name: {skill_name}")

    header = "---\n" + "\n".join(output_lines).rstrip() + "\n---\n"
    return header + text[end + 5 :], dropped


def latest_plugin_skills(home: Path, family: str) -> Path | None:
    root = home / ".claude/plugins/cache" / family / family
    versions = list(root.glob("*/skills"))
    if not versions:
        return None

    def version_key(path: Path) -> tuple[object, ...]:
        return tuple(int(part) if part.isdigit() else part for part in re.split(r"(\d+)", path.parent.name))

    return max(versions, key=version_key)


def collect_sources(home: Path, repo: Path) -> list[tuple[str, Path]]:
    sources: list[tuple[str, Path]] = []

    def add_tree(family: str, root: Path) -> None:
        if root.is_dir():
            sources.extend((family, path.parent) for path in sorted(root.glob("*/SKILL.md")))

    add_tree("pstack", home / ".local/share/pstack-cursor/pstack/skills")

    for candidate in (
        home / ".agents/skills/impeccable",
        home / ".claude/skills/impeccable",
    ):
        if (candidate / "SKILL.md").is_file():
            sources.append(("impeccable", candidate))
            break

    for family in ("caveman", "ponytail"):
        root = latest_plugin_skills(home, family)
        if root:
            add_tree(family, root)

    add_tree("dotfiles", repo / "ai/codex")
    return sources


def make_archive(target: Path, source: Path, skill_name: str, converted_skill: str) -> None:
    with ZipFile(target, "w", ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source.rglob("*")):
            if not path.is_file() or ".DS_Store" in path.parts or "__pycache__" in path.parts:
                continue
            resolved = path.resolve()
            try:
                relative = resolved.relative_to(source.resolve())
            except ValueError:
                continue

            name = (Path(skill_name) / relative).as_posix()
            info = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
            data = converted_skill.encode("utf-8") if relative == Path("SKILL.md") else path.read_bytes()
            archive.writestr(info, data, compress_type=ZIP_DEFLATED, compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path.home() / ".local/share/dotfiles/claude-skill-uploads",
        help="directory for one ZIP per skill (default: ~/.local/share/dotfiles/claude-skill-uploads)",
    )
    args = parser.parse_args()

    home = Path.home()
    repo = Path(__file__).resolve().parent.parent
    sources = collect_sources(home, repo)
    if not sources:
        print("No configured skill sources found.", file=sys.stderr)
        return 1

    output = args.output_dir.expanduser()
    output.mkdir(parents=True, exist_ok=True)
    changed = 0
    current = 0
    expected: set[str] = set()
    skipped = 0
    dropped_fields: set[str] = set()

    with tempfile.TemporaryDirectory(dir=output) as temp_dir:
        temp = Path(temp_dir)
        for family, source in sources:
            skill_name = slug(source.name)
            archive_name = f"{family}--{skill_name}.zip"
            expected.add(archive_name)
            target = output / archive_name
            candidate = temp / archive_name
            try:
                source_text = (source / "SKILL.md").read_text(encoding="utf-8")
                converted, dropped = frontmatter_for_upload(source_text, skill_name)
                make_archive(candidate, source, skill_name, converted)
            except (OSError, UnicodeError, ValueError) as error:
                print(f"[!] Skipped {family}/{source.name}: {error}", file=sys.stderr)
                skipped += 1
                expected.discard(archive_name)
                continue

            dropped_fields.update(dropped)
            if target.exists() and target.read_bytes() == candidate.read_bytes():
                current += 1
            else:
                candidate.replace(target)
                changed += 1

    for path in output.glob("*.zip"):
        if path.name.startswith(MANAGED_PREFIXES) and path.name not in expected:
            path.unlink()

    readme = output / "README.txt"
    readme.write_text(
        "Each ZIP is one skill for Claude's Customize > Skills upload flow. Upload skills separately.\n"
        "The ZIP contains the skill folder at its root.\n"
        "Setup refreshes these local archives; it does not upload or enable skills in your Claude account.\n"
        "Claude Code-only frontmatter fields are removed from the ZIP copies when preparing them for Claude.\n"
        "Original installed skill folders are not modified. Some plugin-specific integrations or external references may not work in Claude Cowork.\n",
        encoding="utf-8",
    )

    print(f"Claude skill ZIPs: {changed} created/refreshed, {current} unchanged, {skipped} skipped")
    print(f"Output: {output}")
    if dropped_fields:
        print("Claude-specific frontmatter omitted: " + ", ".join(sorted(dropped_fields)))
    return 0 if not skipped else 1


if __name__ == "__main__":
    raise SystemExit(main())
