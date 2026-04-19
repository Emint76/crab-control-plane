#!/usr/bin/env python3
"""v1 cross-file validator for the Phase 2 policy/template surface."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml


CANONICAL_CONTRACT_IDS = {
    "task_packet",
    "result_packet",
    "apply_plan",
    "validation_report",
    "admission_decision",
    "placement_decision",
}
PLACEMENT_ARTIFACT_IDS = {
    "apply_plan",
    "validation_report",
    "admission_decision",
    "placement_decision",
}
LEGACY_CONTRACT_IDS = {
    "task-packet",
    "result-packet",
    "apply-plan",
    "validation-report",
    "admission-decision",
    "placement-decision",
}
REQUIRED_OUTPUTS = [
    "validation_report.json",
    "admission_decision.json",
    "placement_decision.json",
    "apply_plan.json",
]
REQUIRED_PLACEMENT_LAYERS = ["notion", "obsidian", "kb", "observability"]
DISALLOWED_PLACEMENT_LAYERS = {"phase2_run_output", "runtime_ready_package", "runtime-ready"}
ALLOWED_ADMISSION_REQUIREMENTS = CANONICAL_CONTRACT_IDS | {"evidence", "review_approval"}
SOURCE_PATHS = {
    "openclaw": "control-plane/runtime/openclaw/openclaw.template.json",
    "tool_policy": "control-plane/runtime/openclaw/tool-policy.template.yaml",
    "routing": "control-plane/runtime/openclaw/agent-routing.template.yaml",
    "placement_policy": "operations/harness-phase2/policy/placement-policy.yaml",
    "admission_policy": "operations/harness-phase2/policy/admission-policy.yaml",
}


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class CheckRecorder:
    def __init__(self, run_id: str) -> None:
        self.run_id = run_id
        self.checks: list[dict[str, Any]] = []
        self.error_seen = False

    def add(
        self,
        name: str,
        status: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
        severity: str | None = None,
    ) -> None:
        check: dict[str, Any] = {
            "name": name,
            "status": status,
            "detail": detail,
            "source_refs": source_refs,
        }
        if severity is not None:
            check["severity"] = severity
        if expected is not None:
            check["expected"] = expected
        if actual is not None:
            check["actual"] = actual
        self.checks.append(check)
        if severity == "error" or status == "fail":
            self.error_seen = True

    def pass_check(
        self,
        name: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        self.add(name, "pass", detail, source_refs=source_refs, expected=expected, actual=actual)

    def fail_check(
        self,
        name: str,
        detail: str,
        *,
        source_refs: list[str],
        expected: Any | None = None,
        actual: Any | None = None,
    ) -> None:
        self.add(
            name,
            "fail",
            detail,
            source_refs=source_refs,
            expected=expected,
            actual=actual,
            severity="error",
        )

    def build_report(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "generated_at": now_utc(),
            "engine_mode": "scaffold",
            "evaluation_mode": "static-v1",
            "status": "fail" if self.error_seen else "pass",
            "checks": self.checks,
        }


def load_json_file(repo_root: Path, rel_path: str, recorder: CheckRecorder, check_name: str) -> dict[str, Any] | None:
    path = repo_root / rel_path
    if not path.is_file():
        recorder.fail_check(
            check_name,
            "Required JSON file is missing.",
            source_refs=[rel_path],
            expected="existing JSON file",
            actual="missing",
        )
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except json.JSONDecodeError as exc:
        recorder.fail_check(
            check_name,
            f"Malformed JSON: {exc}",
            source_refs=[rel_path],
            expected="valid JSON object",
            actual="malformed JSON",
        )
        return None
    except OSError as exc:
        recorder.fail_check(
            check_name,
            f"Unreadable JSON file: {exc}",
            source_refs=[rel_path],
            expected="readable JSON file",
            actual="unreadable",
        )
        return None
    if not isinstance(payload, dict):
        recorder.fail_check(
            check_name,
            "JSON file must contain an object at the top level.",
            source_refs=[rel_path],
            expected="object",
            actual=type(payload).__name__,
        )
        return None
    recorder.pass_check(check_name, "Loaded JSON file.", source_refs=[rel_path], actual="loaded")
    return payload


def load_yaml_file(repo_root: Path, rel_path: str, recorder: CheckRecorder, check_name: str) -> dict[str, Any] | None:
    path = repo_root / rel_path
    if not path.is_file():
        recorder.fail_check(
            check_name,
            "Required YAML file is missing.",
            source_refs=[rel_path],
            expected="existing YAML file",
            actual="missing",
        )
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = yaml.safe_load(handle)
    except yaml.YAMLError as exc:
        recorder.fail_check(
            check_name,
            f"Malformed YAML: {exc}",
            source_refs=[rel_path],
            expected="valid YAML mapping",
            actual="malformed YAML",
        )
        return None
    except OSError as exc:
        recorder.fail_check(
            check_name,
            f"Unreadable YAML file: {exc}",
            source_refs=[rel_path],
            expected="readable YAML file",
            actual="unreadable",
        )
        return None
    if not isinstance(payload, dict):
        recorder.fail_check(
            check_name,
            "YAML file must contain a mapping at the top level.",
            source_refs=[rel_path],
            expected="mapping",
            actual=type(payload).__name__,
        )
        return None
    recorder.pass_check(check_name, "Loaded YAML file.", source_refs=[rel_path], actual="loaded")
    return payload


def require_section(
    payload: dict[str, Any] | None,
    keys: tuple[str, ...],
    expected_type: type,
    recorder: CheckRecorder,
    check_name: str,
    source_ref: str,
) -> Any | None:
    if payload is None:
        return None
    current: Any = payload
    walked: list[str] = []
    for key in keys:
        walked.append(key)
        if not isinstance(current, dict):
            recorder.fail_check(
                check_name,
                f"Expected mapping before resolving {'.'.join(walked)}.",
                source_refs=[source_ref],
                expected="mapping",
                actual=type(current).__name__,
            )
            return None
        if key not in current:
            recorder.fail_check(
                check_name,
                f"Missing required section/key: {'.'.join(walked)}.",
                source_refs=[source_ref],
                expected="present",
                actual="missing",
            )
            return None
        current = current[key]
    if not isinstance(current, expected_type):
        recorder.fail_check(
            check_name,
            f"Section {'.'.join(keys)} has the wrong type.",
            source_refs=[source_ref],
            expected=expected_type.__name__,
            actual=type(current).__name__,
        )
        return None
    recorder.pass_check(
        check_name,
        f"Section {'.'.join(keys)} is present and typed correctly.",
        source_refs=[source_ref],
        actual=type(current).__name__,
    )
    return current


def require_string_list(
    values: Any,
    recorder: CheckRecorder,
    check_name: str,
    source_ref: str,
) -> list[str] | None:
    if not isinstance(values, list):
        recorder.fail_check(
            check_name,
            "Expected a list of strings.",
            source_refs=[source_ref],
            expected="list[str]",
            actual=type(values).__name__,
        )
        return None
    if not all(isinstance(item, str) for item in values):
        recorder.fail_check(
            check_name,
            "Expected every list entry to be a string.",
            source_refs=[source_ref],
            expected="list[str]",
            actual=[type(item).__name__ for item in values],
        )
        return None
    recorder.pass_check(check_name, "List of strings is structurally valid.", source_refs=[source_ref], actual=values)
    return list(values)


def compare_value(
    recorder: CheckRecorder,
    name: str,
    actual: Any,
    expected: Any,
    detail: str,
    source_refs: list[str],
) -> None:
    if actual == expected:
        recorder.pass_check(name, detail, source_refs=source_refs, expected=expected, actual=actual)
    else:
        recorder.fail_check(name, detail, source_refs=source_refs, expected=expected, actual=actual)


def compare_true(
    recorder: CheckRecorder,
    name: str,
    actual: Any,
    detail: str,
    source_refs: list[str],
) -> None:
    compare_value(recorder, name, actual, True, detail, source_refs)


def compare_false(
    recorder: CheckRecorder,
    name: str,
    actual: Any,
    detail: str,
    source_refs: list[str],
) -> None:
    compare_value(recorder, name, actual, False, detail, source_refs)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: validate_policy.py <repo-root> <run-dir>", file=sys.stderr)
        return 2

    repo_root = Path(sys.argv[1]).resolve()
    run_dir = Path(sys.argv[2]).resolve()
    run_id = run_dir.name
    checks_dir = run_dir / "checks"
    checks_dir.mkdir(parents=True, exist_ok=True)
    report_path = checks_dir / "policy_validation.json"

    recorder = CheckRecorder(run_id)

    openclaw = load_json_file(repo_root, SOURCE_PATHS["openclaw"], recorder, "load.openclaw")
    tool_policy = load_yaml_file(repo_root, SOURCE_PATHS["tool_policy"], recorder, "load.tool_policy")
    routing = load_yaml_file(repo_root, SOURCE_PATHS["routing"], recorder, "load.routing")
    placement_policy = load_yaml_file(repo_root, SOURCE_PATHS["placement_policy"], recorder, "load.placement_policy")
    admission_policy = load_yaml_file(repo_root, SOURCE_PATHS["admission_policy"], recorder, "load.admission_policy")

    openclaw_validation = require_section(
        openclaw, ("validation",), dict, recorder, "structure.openclaw.validation", SOURCE_PATHS["openclaw"]
    )
    openclaw_apply = require_section(
        openclaw, ("apply",), dict, recorder, "structure.openclaw.apply", SOURCE_PATHS["openclaw"]
    )
    tool_tools = require_section(
        tool_policy, ("tools",), dict, recorder, "structure.tool_policy.tools", SOURCE_PATHS["tool_policy"]
    )
    tool_gates = require_section(
        tool_policy, ("gates",), dict, recorder, "structure.tool_policy.gates", SOURCE_PATHS["tool_policy"]
    )
    routing_root = require_section(
        routing, ("routing",), dict, recorder, "structure.routing.root", SOURCE_PATHS["routing"]
    )
    placement_roots = require_section(
        placement_policy, ("roots",), dict, recorder, "structure.placement_policy.roots", SOURCE_PATHS["placement_policy"]
    )
    placement_rules = require_section(
        placement_policy, ("rules",), dict, recorder, "structure.placement_policy.rules", SOURCE_PATHS["placement_policy"]
    )
    admission_rules = require_section(
        admission_policy, ("rules",), dict, recorder, "structure.admission_policy.rules", SOURCE_PATHS["admission_policy"]
    )

    tool_codex = require_section(
        tool_tools, ("codex",), dict, recorder, "structure.tool_policy.tools.codex", SOURCE_PATHS["tool_policy"]
    )
    tool_obsidian = require_section(
        tool_tools, ("obsidian",), dict, recorder, "structure.tool_policy.tools.obsidian", SOURCE_PATHS["tool_policy"]
    )
    tool_kb = require_section(
        tool_tools, ("kb",), dict, recorder, "structure.tool_policy.tools.kb", SOURCE_PATHS["tool_policy"]
    )
    gate_validation = require_section(
        tool_gates, ("validation",), dict, recorder, "structure.tool_policy.gates.validation", SOURCE_PATHS["tool_policy"]
    )
    gate_admission = require_section(
        tool_gates, ("admission",), dict, recorder, "structure.tool_policy.gates.admission", SOURCE_PATHS["tool_policy"]
    )
    gate_placement = require_section(
        tool_gates, ("placement",), dict, recorder, "structure.tool_policy.gates.placement", SOURCE_PATHS["tool_policy"]
    )
    gate_apply = require_section(
        tool_gates, ("apply",), dict, recorder, "structure.tool_policy.gates.apply", SOURCE_PATHS["tool_policy"]
    )
    routing_validation = require_section(
        routing_root, ("validation",), dict, recorder, "structure.routing.validation", SOURCE_PATHS["routing"]
    )
    routing_apply = require_section(
        routing_root, ("apply",), dict, recorder, "structure.routing.apply", SOURCE_PATHS["routing"]
    )
    routing_execution = require_section(
        routing_root, ("execution",), dict, recorder, "structure.routing.execution", SOURCE_PATHS["routing"]
    )

    if openclaw_validation is not None:
        compare_value(
            recorder,
            "openclaw.validation.surface",
            openclaw_validation.get("surface"),
            "operations/harness-phase2",
            "OpenClaw validation surface must point to the Phase 2 scaffold surface.",
            [SOURCE_PATHS["openclaw"]],
        )
        compare_value(
            recorder,
            "openclaw.validation.entrypoint",
            openclaw_validation.get("entrypoint"),
            "operations/harness-phase2/bin/run_phase2_bundle.sh",
            "OpenClaw validation entrypoint must point to the Phase 2 bundle.",
            [SOURCE_PATHS["openclaw"]],
        )
        required_outputs = require_string_list(
            openclaw_validation.get("required_outputs"),
            recorder,
            "openclaw.validation.required_outputs.structure",
            SOURCE_PATHS["openclaw"],
        )
        if required_outputs is not None:
            missing_outputs = [item for item in REQUIRED_OUTPUTS if item not in required_outputs]
            if missing_outputs:
                recorder.fail_check(
                    "openclaw.validation.required_outputs.contents",
                    "OpenClaw required_outputs is missing required Phase 2 reports.",
                    source_refs=[SOURCE_PATHS["openclaw"]],
                    expected=REQUIRED_OUTPUTS,
                    actual=required_outputs,
                )
            else:
                recorder.pass_check(
                    "openclaw.validation.required_outputs.contents",
                    "OpenClaw required_outputs contains the expected Phase 2 reports.",
                    source_refs=[SOURCE_PATHS["openclaw"]],
                    expected=REQUIRED_OUTPUTS,
                    actual=required_outputs,
                )

            output_stems = [item.removesuffix(".json") for item in required_outputs if item.endswith(".json")]
            naming_ok = all(stem in PLACEMENT_ARTIFACT_IDS for stem in output_stems)
            if naming_ok:
                recorder.pass_check(
                    "openclaw.validation.required_outputs.naming",
                    "OpenClaw required_outputs uses the expected snake_case artifact filenames.",
                    source_refs=[SOURCE_PATHS["openclaw"]],
                    expected=sorted(PLACEMENT_ARTIFACT_IDS),
                    actual=output_stems,
                )
            else:
                recorder.fail_check(
                    "openclaw.validation.required_outputs.naming",
                    "OpenClaw required_outputs contains a non-canonical Phase 2 artifact filename.",
                    source_refs=[SOURCE_PATHS["openclaw"]],
                    expected=sorted(PLACEMENT_ARTIFACT_IDS),
                    actual=output_stems,
                )
    else:
        required_outputs = None

    if openclaw_apply is not None:
        compare_value(
            recorder,
            "openclaw.apply.mode",
            openclaw_apply.get("mode"),
            "controlled-apply",
            "OpenClaw apply.mode must remain controlled-apply.",
            [SOURCE_PATHS["openclaw"]],
        )
        compare_false(
            recorder,
            "openclaw.apply.live_write_allowed",
            openclaw_apply.get("live_write_allowed"),
            "OpenClaw must forbid live writes in Phase 2.",
            [SOURCE_PATHS["openclaw"]],
        )

    if routing_validation is not None:
        compare_value(
            recorder,
            "routing.validation.surface",
            routing_validation.get("surface"),
            "operations/harness-phase2",
            "Routing validation surface must match the Phase 2 surface.",
            [SOURCE_PATHS["routing"]],
        )
    if routing_apply is not None:
        compare_value(
            recorder,
            "routing.apply.mode",
            routing_apply.get("mode"),
            "controlled-apply",
            "Routing apply.mode must remain controlled-apply.",
            [SOURCE_PATHS["routing"]],
        )
        compare_true(
            recorder,
            "routing.apply.phase2_live_writes_forbidden",
            routing_apply.get("phase2_live_writes_forbidden"),
            "Routing must explicitly forbid Phase 2 live writes.",
            [SOURCE_PATHS["routing"]],
        )
    if routing_execution is not None:
        compare_value(
            recorder,
            "routing.execution.runtime_ready_source",
            routing_execution.get("runtime_ready_source"),
            "operations/harness-phase2/runs/<RUN_ID>/output/runtime-ready/",
            "Routing execution.runtime_ready_source must point to the run-scoped runtime-ready output.",
            [SOURCE_PATHS["routing"]],
        )

    if gate_apply is not None:
        compare_value(
            recorder,
            "tool_policy.gates.apply.mode",
            gate_apply.get("mode"),
            "controlled-apply",
            "tool-policy gates.apply.mode must remain controlled-apply.",
            [SOURCE_PATHS["tool_policy"]],
        )
        compare_false(
            recorder,
            "tool_policy.gates.apply.live_target_allowed",
            gate_apply.get("live_target_allowed"),
            "tool-policy must not allow live targets for Phase 2 apply.",
            [SOURCE_PATHS["tool_policy"]],
        )

    if required_outputs is not None:
        if "validation_report.json" in required_outputs and routing_validation is not None:
            compare_true(
                recorder,
                "consistency.required_output.validation_report.routing",
                routing_validation.get("require_validation_report"),
                "routing.validation.require_validation_report must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["routing"]],
            )
        if "validation_report.json" in required_outputs and gate_validation is not None:
            compare_true(
                recorder,
                "consistency.required_output.validation_report.gate",
                gate_validation.get("enabled"),
                "tool-policy gates.validation.enabled must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["tool_policy"]],
            )
        if "admission_decision.json" in required_outputs and routing_validation is not None:
            compare_true(
                recorder,
                "consistency.required_output.admission_decision.routing",
                routing_validation.get("require_admission_decision"),
                "routing.validation.require_admission_decision must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["routing"]],
            )
        if "admission_decision.json" in required_outputs and gate_admission is not None:
            compare_true(
                recorder,
                "consistency.required_output.admission_decision.gate",
                gate_admission.get("enabled"),
                "tool-policy gates.admission.enabled must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["tool_policy"]],
            )
        if "placement_decision.json" in required_outputs and routing_validation is not None:
            compare_true(
                recorder,
                "consistency.required_output.placement_decision.routing",
                routing_validation.get("require_placement_decision"),
                "routing.validation.require_placement_decision must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["routing"]],
            )
        if "placement_decision.json" in required_outputs and gate_placement is not None:
            compare_true(
                recorder,
                "consistency.required_output.placement_decision.gate",
                gate_placement.get("enabled"),
                "tool-policy gates.placement.enabled must agree with openclaw required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["tool_policy"]],
            )
        if "apply_plan.json" in required_outputs and openclaw_apply is not None:
            compare_true(
                recorder,
                "consistency.required_output.apply_plan.openclaw",
                openclaw_apply.get("require_apply_plan"),
                "openclaw.apply.require_apply_plan must agree with required_outputs.",
                [SOURCE_PATHS["openclaw"]],
            )
        if "apply_plan.json" in required_outputs and gate_apply is not None:
            compare_true(
                recorder,
                "consistency.required_output.apply_plan.gate",
                gate_apply.get("require_apply_plan"),
                "tool-policy gates.apply.require_apply_plan must agree with required_outputs.",
                [SOURCE_PATHS["openclaw"], SOURCE_PATHS["tool_policy"]],
            )

    if gate_validation is not None and routing_apply is not None:
        if gate_validation.get("required_before_apply") is True:
            compare_true(
                recorder,
                "consistency.gates.validation_before_apply",
                routing_apply.get("render_before_execution"),
                "render_before_execution must remain true when validation is required before apply.",
                [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["routing"]],
            )
        else:
            recorder.pass_check(
                "consistency.gates.validation_before_apply",
                "No contradiction: validation.required_before_apply is not forcing render_before_execution.",
                source_refs=[SOURCE_PATHS["tool_policy"], SOURCE_PATHS["routing"]],
                actual=gate_validation.get("required_before_apply"),
            )

    if gate_apply is not None and openclaw_apply is not None and gate_apply.get("require_apply_plan") is True:
        compare_true(
            recorder,
            "consistency.gates.apply_plan_requirement",
            openclaw_apply.get("require_apply_plan"),
            "openclaw.apply.require_apply_plan must stay aligned with tool-policy.",
            [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["openclaw"]],
        )

    if placement_roots is not None:
        for layer in REQUIRED_PLACEMENT_LAYERS:
            compare_true(
                recorder,
                f"placement_policy.roots.{layer}",
                layer in placement_roots,
                f"placement-policy must define a root for {layer}.",
                [SOURCE_PATHS["placement_policy"]],
            )
        disallowed_found = sorted(DISALLOWED_PLACEMENT_LAYERS.intersection(placement_roots.keys()))
        if disallowed_found:
            recorder.fail_check(
                "placement_policy.roots.disallowed_layers",
                "placement-policy must not introduce runtime-ready or phase2_run_output layers.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                expected="no runtime-ready placement layer ids",
                actual=disallowed_found,
            )
        else:
            recorder.pass_check(
                "placement_policy.roots.disallowed_layers",
                "placement-policy does not introduce disallowed placement layer ids.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
            )
        root_paths = {layer: placement_roots.get(layer) for layer in sorted(placement_roots)}
        invalid_root_paths = {
            layer: path for layer, path in root_paths.items() if isinstance(path, str) and "operations/harness-phase2/runs/" in path
        }
        if invalid_root_paths:
            recorder.fail_check(
                "placement_policy.roots.runtime_ready_paths",
                "placement-policy roots must not treat runtime-ready output as a placement layer path.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                expected="no roots under operations/harness-phase2/runs/",
                actual=invalid_root_paths,
            )
        else:
            recorder.pass_check(
                "placement_policy.roots.runtime_ready_paths",
                "placement-policy roots stay separate from runtime-ready output paths.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                actual=root_paths,
            )

    if admission_rules is not None:
        for layer in ("kb", "observability", "obsidian"):
            compare_true(
                recorder,
                f"admission_policy.rules.{layer}",
                layer in admission_rules,
                f"admission-policy must define a rule for {layer}.",
                [SOURCE_PATHS["admission_policy"]],
            )

    if placement_rules is not None and placement_roots is not None:
        rule_keys = sorted(placement_rules.keys())
        unexpected_rule_keys = [key for key in rule_keys if key not in PLACEMENT_ARTIFACT_IDS]
        if unexpected_rule_keys:
            recorder.fail_check(
                "placement_policy.rules.naming",
                "placement-policy contains a non-canonical placement artifact id.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                expected=sorted(PLACEMENT_ARTIFACT_IDS),
                actual=unexpected_rule_keys,
            )
        else:
            recorder.pass_check(
                "placement_policy.rules.naming",
                "placement-policy uses canonical snake_case placement artifact ids.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                expected=sorted(PLACEMENT_ARTIFACT_IDS),
                actual=rule_keys,
            )
        if "runtime_ready_package" in placement_rules:
            recorder.fail_check(
                "placement_policy.rules.runtime_ready_package",
                "runtime_ready_package must not be treated as a placement artifact.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
                expected="absent",
                actual="present",
            )
        else:
            recorder.pass_check(
                "placement_policy.rules.runtime_ready_package",
                "runtime_ready_package is not treated as a placement artifact.",
                source_refs=[SOURCE_PATHS["placement_policy"]],
            )

        for artifact_id in sorted(placement_rules):
            rule = placement_rules[artifact_id]
            check_name = f"placement_policy.rules.{artifact_id}.target_layer"
            if not isinstance(rule, dict):
                recorder.fail_check(
                    check_name,
                    "placement-policy rule must be a mapping.",
                    source_refs=[SOURCE_PATHS["placement_policy"]],
                    expected="mapping",
                    actual=type(rule).__name__,
                )
                continue
            target_layer = rule.get("target_layer")
            if target_layer in placement_roots and target_layer not in DISALLOWED_PLACEMENT_LAYERS:
                recorder.pass_check(
                    check_name,
                    "placement-policy rule targets a known placement layer.",
                    source_refs=[SOURCE_PATHS["placement_policy"]],
                    expected=sorted(placement_roots.keys()),
                    actual=target_layer,
                )
            else:
                recorder.fail_check(
                    check_name,
                    "placement-policy rule targets an unknown or disallowed layer.",
                    source_refs=[SOURCE_PATHS["placement_policy"]],
                    expected=sorted(placement_roots.keys()),
                    actual=target_layer,
                )

        if required_outputs is not None:
            required_placement_rules = sorted(
                {
                    item.removesuffix(".json")
                    for item in required_outputs
                    if item.endswith(".json") and item.removesuffix(".json") in PLACEMENT_ARTIFACT_IDS
                }
            )
            missing_required_rules = [artifact_id for artifact_id in required_placement_rules if artifact_id not in placement_rules]
            if missing_required_rules:
                recorder.fail_check(
                    "consistency.placement.required_rules_present",
                    "placement-policy is missing a required rule for an artifact implied by openclaw.validation.required_outputs.",
                    source_refs=[SOURCE_PATHS["openclaw"], SOURCE_PATHS["placement_policy"]],
                    expected=required_placement_rules,
                    actual={"present": rule_keys, "missing": missing_required_rules},
                )
            else:
                recorder.pass_check(
                    "consistency.placement.required_rules_present",
                    "placement-policy contains rules for every placement-governed artifact implied by openclaw.validation.required_outputs.",
                    source_refs=[SOURCE_PATHS["openclaw"], SOURCE_PATHS["placement_policy"]],
                    expected=required_placement_rules,
                    actual=rule_keys,
                )

    if gate_placement is not None and placement_roots is not None:
        placement_required_for = require_string_list(
            gate_placement.get("required_for"),
            recorder,
            "tool_policy.gates.placement.required_for.structure",
            SOURCE_PATHS["tool_policy"],
        )
        if placement_required_for is not None:
            for target in placement_required_for:
                if target in placement_roots and target not in DISALLOWED_PLACEMENT_LAYERS:
                    recorder.pass_check(
                        f"consistency.gates.placement.required_for.{target}",
                        "tool-policy placement gate references a known placement layer.",
                        source_refs=[SOURCE_PATHS["tool_policy"], SOURCE_PATHS["placement_policy"]],
                        expected=sorted(placement_roots.keys()),
                        actual=target,
                    )
                else:
                    recorder.fail_check(
                        f"consistency.gates.placement.required_for.{target}",
                        "tool-policy placement gate references an unknown or disallowed placement layer.",
                        source_refs=[SOURCE_PATHS["tool_policy"], SOURCE_PATHS["placement_policy"]],
                        expected=sorted(placement_roots.keys()),
                        actual=target,
                    )

    if gate_admission is not None and admission_rules is not None:
        admission_required_for = require_string_list(
            gate_admission.get("required_for"),
            recorder,
            "tool_policy.gates.admission.required_for.structure",
            SOURCE_PATHS["tool_policy"],
        )
        if admission_required_for is not None:
            for target in admission_required_for:
                compare_true(
                    recorder,
                    f"consistency.gates.admission.required_for.{target}",
                    target in admission_rules,
                    "tool-policy admission gate must reference an admission-policy rule.",
                    [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["admission_policy"]],
                )

    if tool_codex is not None:
        output_contracts = require_string_list(
            tool_codex.get("output_contracts"),
            recorder,
            "tool_policy.tools.codex.output_contracts.structure",
            SOURCE_PATHS["tool_policy"],
        )
        if output_contracts is not None:
            invalid_contract_ids = [item for item in output_contracts if item not in CANONICAL_CONTRACT_IDS]
            if invalid_contract_ids:
                recorder.fail_check(
                    "tool_policy.tools.codex.output_contracts.naming",
                    "tool-policy codex output_contracts contains a non-canonical contract id.",
                    source_refs=[SOURCE_PATHS["tool_policy"]],
                    expected=sorted(CANONICAL_CONTRACT_IDS),
                    actual=invalid_contract_ids,
                )
            else:
                recorder.pass_check(
                    "tool_policy.tools.codex.output_contracts.naming",
                    "tool-policy codex output_contracts uses canonical snake_case ids.",
                    source_refs=[SOURCE_PATHS["tool_policy"]],
                    expected=sorted(CANONICAL_CONTRACT_IDS),
                    actual=output_contracts,
                )

    if admission_rules is not None:
        for layer in sorted(admission_rules):
            rule = admission_rules[layer]
            if not isinstance(rule, dict):
                recorder.fail_check(
                    f"admission_policy.rules.{layer}.structure",
                    "admission-policy rule must be a mapping.",
                    source_refs=[SOURCE_PATHS["admission_policy"]],
                    expected="mapping",
                    actual=type(rule).__name__,
                )
                continue
            requires = rule.get("requires", [])
            if "requires" not in rule:
                recorder.fail_check(
                    f"admission_policy.rules.{layer}.requires",
                    "admission-policy rule is missing a requires list.",
                    source_refs=[SOURCE_PATHS["admission_policy"]],
                    expected="requires list",
                    actual="missing",
                )
                continue
            require_list = require_string_list(
                requires,
                recorder,
                f"admission_policy.rules.{layer}.requires.structure",
                SOURCE_PATHS["admission_policy"],
            )
            if require_list is None:
                continue
            invalid_tokens = [item for item in require_list if item not in ALLOWED_ADMISSION_REQUIREMENTS]
            if invalid_tokens:
                recorder.fail_check(
                    f"admission_policy.rules.{layer}.requires.naming",
                    "admission-policy rule contains a non-canonical or unsupported requirement token.",
                    source_refs=[SOURCE_PATHS["admission_policy"]],
                    expected=sorted(ALLOWED_ADMISSION_REQUIREMENTS),
                    actual=invalid_tokens,
                )
            else:
                recorder.pass_check(
                    f"admission_policy.rules.{layer}.requires.naming",
                    "admission-policy rule uses canonical snake_case ids where contract ids are referenced.",
                    source_refs=[SOURCE_PATHS["admission_policy"]],
                    expected=sorted(ALLOWED_ADMISSION_REQUIREMENTS),
                    actual=require_list,
                )

    if tool_kb is not None and admission_rules is not None:
        if tool_kb.get("requires_admission_decision") is True:
            compare_true(
                recorder,
                "consistency.kb.requires_admission_decision",
                "kb" in admission_rules,
                "tool-policy kb admission requirement must be backed by an admission-policy rule.",
                [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["admission_policy"]],
            )

    if tool_kb is not None and placement_roots is not None:
        if tool_kb.get("requires_placement_decision") is True:
            compare_true(
                recorder,
                "consistency.kb.requires_placement_decision",
                "kb" in placement_roots,
                "tool-policy kb placement requirement must be backed by placement roots/layer semantics.",
                [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["placement_policy"]],
            )

    if tool_obsidian is not None and placement_roots is not None:
        if tool_obsidian.get("requires_placement_decision") is True:
            compare_true(
                recorder,
                "consistency.obsidian.requires_placement_decision",
                "obsidian" in placement_roots,
                "tool-policy obsidian placement requirement must be backed by placement roots/layer semantics.",
                [SOURCE_PATHS["tool_policy"], SOURCE_PATHS["placement_policy"]],
            )

    if openclaw_apply is not None and routing_execution is not None:
        compare_value(
            recorder,
            "consistency.runtime_ready_source",
            routing_execution.get("runtime_ready_source"),
            openclaw_apply.get("render_target"),
            "routing.execution.runtime_ready_source must match openclaw.apply.render_target.",
            [SOURCE_PATHS["routing"], SOURCE_PATHS["openclaw"]],
        )

    legacy_hits: dict[str, list[str]] = {}
    structured_string_sources = [
        (SOURCE_PATHS["openclaw"], openclaw),
        (SOURCE_PATHS["tool_policy"], tool_policy),
        (SOURCE_PATHS["routing"], routing),
        (SOURCE_PATHS["placement_policy"], placement_policy),
        (SOURCE_PATHS["admission_policy"], admission_policy),
    ]
    for source_ref, payload in structured_string_sources:
        if payload is None:
            continue
        hits: list[str] = []

        def walk(value: Any) -> None:
            if isinstance(value, dict):
                for nested_value in value.values():
                    walk(nested_value)
            elif isinstance(value, list):
                for nested_value in value:
                    walk(nested_value)
            elif isinstance(value, str) and value in LEGACY_CONTRACT_IDS:
                hits.append(value)

        walk(payload)
        if hits:
            legacy_hits[source_ref] = sorted(set(hits))

    if legacy_hits:
        recorder.fail_check(
            "naming.legacy_contract_ids",
            "Structured control-plane files still contain legacy hyphenated contract ids.",
            source_refs=sorted(legacy_hits.keys()),
            expected=sorted(CANONICAL_CONTRACT_IDS),
            actual=legacy_hits,
        )
    else:
        recorder.pass_check(
            "naming.legacy_contract_ids",
            "Structured control-plane files do not contain legacy hyphenated contract ids.",
            source_refs=sorted(SOURCE_PATHS.values()),
            expected=sorted(CANONICAL_CONTRACT_IDS),
        )

    report = recorder.build_report()
    with report_path.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    return 1 if recorder.error_seen else 0


if __name__ == "__main__":
    raise SystemExit(main())
