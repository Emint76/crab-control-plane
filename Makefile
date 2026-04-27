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
