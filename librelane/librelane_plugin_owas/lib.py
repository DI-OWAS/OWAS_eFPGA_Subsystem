# SPDX-License-Identifier: Apache-2.0
"""
Liberty edits on the macro timing models written by ``OpenROAD.STAPostPNR``.

``Lib.CombinationalClockArcs`` turns a macro's clock feed-through (a clock input
driving a clock output through buffers only) into one combinational
``positive_unate`` arc. OpenSTA's ``write_timing_model`` models such an output as a
register output (``rising_edge`` + ``falling_edge`` arcs from the clock input), so in
the parent design the clock stops at the macro unless a generated clock sits on the
output pin. With the combinational arc, the parent's clock propagates through it.
"""
import os
import re
from pathlib import Path
from typing import List, Optional, Tuple

from librelane.common import Path as StatePath
from librelane.config import Variable
from librelane.logging import verbose
from librelane.state import DesignFormat, State
from librelane.steps import Step, StepException


def _group_end(text: str, open_brace: int) -> int:
    """Index just past the ``}`` that closes the ``{`` at ``open_brace``."""
    depth = 0
    for i in range(open_brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    raise ValueError("unbalanced braces")


def _groups(text: str, name: str, start: int = 0, end: Optional[int] = None):
    """(start, body_start, end) of every ``name(...) {`` group in text[start:end]."""
    end = len(text) if end is None else end
    pattern = re.compile(r"\b" + re.escape(name) + r"\s*\(([^)]*)\)\s*\{")
    pos = start
    while True:
        m = pattern.search(text, pos, end)
        if m is None:
            return
        group_end = _group_end(text, m.end() - 1)
        yield m.group(1).strip().strip('"'), m.start(), m.end(), group_end
        pos = group_end


def _attr(body: str, name: str) -> Optional[str]:
    m = re.search(r"\b" + re.escape(name) + r"\s*:\s*\"?([^\";]*)\"?\s*;", body)
    return m.group(1).strip() if m else None


def _table(body: str, name: str) -> str:
    """The ``name(template) { ... }`` group in body; exactly one must exist."""
    found = [body[s:e] for _, s, _, e in _groups(body, name)]
    if len(found) != 1:
        raise ValueError(f"expected one {name} table, found {len(found)}")
    return found[0]


def combinational_clock_arc(lib: str, related_pin: str, pin: str) -> Tuple[str, int]:
    """
    Replaces the ``rising_edge`` and ``falling_edge`` arcs related_pin -> pin of every
    cell in lib with one combinational positive_unate arc: cell_rise/rise_transition
    from the rising_edge arc, cell_fall/fall_transition from the falling_edge arc.
    Returns the new text and the number of pins changed.
    """
    edits = []
    for _, _, cell_body, cell_end in _groups(lib, "cell"):
        for name, pin_start, pin_body, pin_end in _groups(lib, "pin", cell_body, cell_end):
            if name != pin:
                continue
            arcs = {}
            for _, t_start, t_body, t_end in _groups(lib, "timing", pin_body, pin_end):
                body = lib[t_body : t_end - 1]
                if _attr(body, "related_pin") != related_pin:
                    continue
                kind = _attr(body, "timing_type")
                if kind in arcs:
                    raise ValueError(f"pin {pin}: two {kind} arcs from {related_pin}")
                arcs[kind] = (t_start, t_end, body)
            if set(arcs) != {"rising_edge", "falling_edge"}:
                raise ValueError(
                    f"pin {pin}: expected rising_edge + falling_edge arcs from "
                    f"{related_pin}, found {sorted(arcs, key=str)}"
                )
            rise = arcs["rising_edge"][2]
            fall = arcs["falling_edge"][2]
            indent = re.search(r"\n([ \t]*)timing\s*\(", lib[pin_body - 1 : arcs["rising_edge"][1]])
            ind = indent.group(1) if indent else "      "
            new = (
                f"timing() {{\n"
                f'{ind}  related_pin : "{related_pin}";\n'
                f"{ind}  timing_sense : positive_unate;\n"
                f"{ind}  timing_type : combinational;\n"
                + "".join(
                    f"\t{_table(src, table)}\n"
                    for src, table in (
                        (rise, "cell_rise"),
                        (rise, "rise_transition"),
                        (fall, "cell_fall"),
                        (fall, "fall_transition"),
                    )
                )
                + f"{ind}}}"
            )
            first, second = sorted(
                (arcs["rising_edge"][:2], arcs["falling_edge"][:2])
            )
            # first arc -> new arc; second arc (and the whitespace before it) removed
            gap_start = second[0]
            while gap_start > first[1] and lib[gap_start - 1] in " \t\n":
                gap_start -= 1
            edits.append((first[0], first[1], new))
            edits.append((gap_start, second[1], ""))
    for start, end, text in sorted(edits, reverse=True):
        lib = lib[:start] + text + lib[end:]
    return lib, len(edits) // 2


@Step.factory.register()
class CombinationalClockArcs(Step):
    """
    Rewrites clock feed-through arcs in the macro's own timing models (the LIB views
    of the state, one per STA corner) as combinational arcs, see the module doc.
    Insert it after ``OpenROAD.STAPostPNR``.
    """

    id = "Lib.CombinationalClockArcs"
    name = "Combinational Clock Arcs"

    inputs = [DesignFormat.LIB]
    outputs = [DesignFormat.LIB]

    config_vars = [
        Variable(
            "LIB_COMBINATIONAL_CLOCK_ARCS",
            Optional[List[str]],
            "Clock feed-through arcs ``<clock input>-><clock output>`` (e.g. "
            "``clk_i->clk_o``) to rewrite as one combinational positive_unate arc in "
            "the LIB views. Each must have exactly a rising_edge and a falling_edge arc "
            "in every corner. If unset, the step is skipped.",
            default=None,
        ),
    ]

    def run(self, state_in: State, **kwargs):
        arcs = self.config["LIB_COMBINATIONAL_CLOCK_ARCS"]
        if not arcs:
            self.warn("LIB_COMBINATIONAL_CLOCK_ARCS is not set; skipping.")
            return {}, {}
        libs = state_in.get(DesignFormat.LIB)
        if not isinstance(libs, dict) or not libs:
            raise StepException("No LIB views in the input state (run after OpenROAD.STAPostPNR).")
        out = {}
        for corner, path in libs.items():
            text = Path(path).read_text(encoding="utf8")
            for arc in arcs:
                related_pin, sep, pin = (s.strip() for s in arc.partition("->"))
                if not sep or not related_pin or not pin:
                    raise StepException(f"Malformed LIB_COMBINATIONAL_CLOCK_ARCS entry '{arc}'.")
                try:
                    text, count = combinational_clock_arc(text, related_pin, pin)
                except ValueError as e:
                    raise StepException(f"{corner}: {e}") from e
                if count == 0:
                    raise StepException(f"{corner}: no pin {pin} in {path}.")
                verbose(f"{corner}: {related_pin}->{pin} combinational ({count} pin(s))")
            target = os.path.join(self.step_dir, corner, os.path.basename(str(path)))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            Path(target).write_text(text, encoding="utf8")
            # State views must be librelane.common.Path (a str subclass), not pathlib.Path
            out[corner] = StatePath(target)
        return {DesignFormat.LIB: out}, {}
