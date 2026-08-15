#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "yaml"

root = Pathname.new(ARGV.fetch(0, ".")).expand_path
workflow_dir = root.join(".github", "workflows")

unless workflow_dir.directory?
  warn "workflow directory missing: #{workflow_dir}"
  exit 1
end

retired_workflows = %w[
  pr14-current-main-reconciliation.yml
  pr14-protected-main-repair.yml
  v71r12-validation-failure-recorder.yml
  v71r12-validation-monitor.yml
].freeze

errors = []
workflows = Dir.glob(workflow_dir.join("*.{yml,yaml}").to_s).sort
errors << "no workflow files found" if workflows.empty?

workflows.each do |path_string|
  path = Pathname.new(path_string)
  relative = path.relative_path_from(root).to_s
  basename = path.basename.to_s
  content = path.read(encoding: "UTF-8")

  if basename.start_with?("temp-") || basename.start_with?("temporary-")
    errors << "#{relative}: temporary workflows are forbidden on protected source"
  end
  if retired_workflows.include?(basename)
    errors << "#{relative}: retired one-shot repair workflow must not return"
  end
  if content.match?(/^\s*pull_request_target\s*:/)
    errors << "#{relative}: pull_request_target is forbidden by default"
  end

  begin
    document = YAML.safe_load(
      content,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: true,
    )
    errors << "#{relative}: top-level YAML must be a mapping" unless document.is_a?(Hash)
  rescue Psych::Exception => error
    errors << "#{relative}: invalid YAML: #{error.message.lines.first.to_s.strip}"
  end

  content.each_line.with_index(1) do |line, line_number|
    match = line.match(/^\s*(?:-\s*)?uses:\s*([^\s#]+)\s*(?:#.*)?$/)
    next unless match

    reference = match[1].delete_prefix("\"").delete_suffix("\"")
    reference = reference.delete_prefix("'").delete_suffix("'")

    next if reference.start_with?("./")

    if reference.start_with?("docker://")
      unless reference.match?(/@sha256:[0-9a-f]{64}\z/)
        errors << "#{relative}:#{line_number}: container action must use an immutable sha256 digest"
      end
      next
    end

    unless reference.match?(/\A[^@\s]+@[0-9a-f]{40}\z/)
      errors << "#{relative}:#{line_number}: action must be pinned to an immutable 40-character commit SHA"
    end
  end
end

if errors.any?
  warn "WORKFLOW_INTEGRITY_FAILED count=#{errors.length}"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "WORKFLOW_INTEGRITY_PASS workflows=#{workflows.length}"
