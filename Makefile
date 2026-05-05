smoke-e2e:
	bash operations/harness-e2e/tests/test_smoke_e2e.sh

phase2-ci:
	bash operations/harness-phase2/tests/test_run_dir_invariants.sh
	bash operations/harness-phase2/tests/test_preflight_wrong_root_scan.sh
	bash operations/harness-phase2/tests/run_fixture_smoke.sh
	bash operations/harness-phase2/tests/test_standalone_check_tools.sh
	bash operations/harness-phase2/tests/test_check_layer_profile.sh
	bash operations/harness-phase2/tests/test_observability_emitter.sh

phase3-ci:
	python -m compileall operations/harness-phase3/bin
	bash operations/harness-phase3/tests/test_run_dir_invariants.sh
	bash operations/harness-phase3/tests/test_fail_closed_and_evidence.sh
	bash operations/harness-phase3/tests/test_execution_target_schema_contract.sh
	bash operations/harness-phase3/tests/test_report_shape.sh

phase4-ci:
	python -m compileall operations/harness-phase3/bin
	bash operations/harness-phase4/tests/test_phase4_wrapper.sh

orchestration-ci:
	bash operations/harness-orchestration/tests/test_orchestration_wrapper.sh

openclaw-dryrun-ci:
	bash operations/harness-openclaw-dryrun/tests/test_openclaw_dry_run.sh

disposable-target-validation-ci:
	bash operations/harness-openclaw-target-validation/tests/test_disposable_target_path_validation.sh

no-secret-leakage-ci:
	bash operations/harness-openclaw-safety-validation/tests/test_no_secret_leakage_validation.sh

controlled-disposable-apply-ci:
	bash operations/harness-openclaw-disposable-apply/tests/test_controlled_disposable_apply.sh

local-target-selector-ci:
	bash operations/harness-openclaw-local-selector/tests/test_local_target_selector_layer.sh

openclaw-local-proof-ci:
	bash operations/harness-openclaw-local-proof/tests/test_full_local_disposable_cycle.sh

live-preexecution-ci:
	bash operations/harness-openclaw-live-precheck/tests/test_live_preexecution_gate.sh

live-secret-retention-ci:
	bash operations/harness-openclaw-live-retention/tests/test_secret_retention_surface.sh

live-execution-prep-ci:
	bash operations/harness-openclaw-live-execution-prep/tests/test_live_execution_prep.sh

live-wrapper-intake-ci:
	bash operations/harness-openclaw-live-wrapper-intake/tests/test_live_wrapper_intake.sh

live-wrapper-preflight-ci:
	bash operations/harness-openclaw-live-wrapper/tests/test_live_wrapper_preflight.sh

live-material-resolution-ci:
	bash operations/harness-openclaw-live-material-resolution/tests/test_live_material_resolution.sh

live-secret-session-ci:
	bash operations/harness-openclaw-live-secret-session/tests/test_live_secret_session.sh

live-wrapper-execution-owner-ci:
	bash operations/harness-openclaw-live-wrapper/tests/test_live_wrapper_execution_owner.sh

openclaw-local-ci:
	$(MAKE) orchestration-ci
	$(MAKE) openclaw-dryrun-ci
	$(MAKE) disposable-target-validation-ci
	$(MAKE) no-secret-leakage-ci
	$(MAKE) controlled-disposable-apply-ci
	$(MAKE) local-target-selector-ci
	$(MAKE) openclaw-local-proof-ci
