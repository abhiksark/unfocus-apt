# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class WorkflowContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  WORKFLOWS = {
    "alpha" => File.join(ROOT, ".github/workflows/update-alpha.yml"),
    "beta" => File.join(ROOT, ".github/workflows/update-beta.yml")
  }.freeze

  def test_channel_workflows_accept_only_their_guarded_source_dispatch
    WORKFLOWS.each do |channel, path|
      workflow = YAML.safe_load(File.read(path))

      assert_equal(
        { "repository_dispatch" => { "types" => ["unfocus-#{channel}-published"] } },
        workflow.fetch(true),
        channel
      )
    end
  end

  def test_channel_workflows_verify_exact_release_identity_and_immutability
    WORKFLOWS.each do |channel, path|
      workflow = YAML.safe_load(File.read(path))
      steps = workflow.fetch("jobs").fetch("update").fetch("steps")
      release_step = steps.find { |step| step["id"] == "release" }
      env = release_step.fetch("env")
      run = release_step.fetch("run")

      assert_equal(
        {
          "GH_TOKEN" => "${{ secrets.GITHUB_TOKEN }}",
          "PAYLOAD_RELEASE_ID" => "${{ github.event.client_payload.release_id }}",
          "PAYLOAD_SOURCE_REPOSITORY" => "${{ github.event.client_payload.source_repository }}",
          "PAYLOAD_TAG" => "${{ github.event.client_payload.tag_name }}"
        },
        env,
        channel
      )
      assert_includes run, "RETURNED_RELEASE_ID=$(jq -r .id \"$RUNNER_TEMP/release.json\")", channel
      assert_includes run, "RETURNED_TAG_NAME=$(jq -r .tag_name \"$RUNNER_TEMP/release.json\")", channel
      assert_includes run, '[ "$RETURNED_RELEASE_ID" = "$RELEASE_ID" ]', channel
      assert_includes run, '[ "$RETURNED_TAG_NAME" = "$TAG_NAME" ]', channel
      assert_includes run, 'IMMUTABLE=$(jq -r .immutable "$RUNNER_TEMP/release.json")', channel
      assert_includes run, '[ "$IMMUTABLE" = true ]', channel
    end
  end

  def test_recovery_documentation_uses_guarded_source_workflows
    operator_guide = File.read(File.join(ROOT, "OPERATOR.md"))

    assert_includes operator_guide, "On `abhiksark/unfocus`, use the workflow matching the release channel"
    assert_includes operator_guide, "Actions → Dispatch APT alpha update → Run workflow → vX.Y.Z-alpha.N"
    assert_includes operator_guide, "Actions → Dispatch APT beta update  → Run workflow → vX.Y.Z-beta.N"
  end
end
