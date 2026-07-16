import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

import {
  evaluateHealth,
  parseHealthReport,
  unavailableReport,
} from '../skills/agentbox-doctor/scripts/check-host-lib.js';

const checkCatalog = JSON.parse(
  readFileSync(
    new URL('../skills/agentbox-doctor/references/checks.json', import.meta.url),
    'utf8',
  ),
);
const remediationCatalog = JSON.parse(
  readFileSync(
    new URL('../skills/agentbox-doctor/references/remediations.json', import.meta.url),
    'utf8',
  ),
);

const healthyValues = {
  timestamp: '2026-07-16T12:00:00Z',
  agentbox_version: '1.0.0-beta.6',
  expected_hostname: 'TANAABAGENTBOX1',
  computer_name: 'TANAABAGENTBOX1',
  host_name: 'TANAABAGENTBOX1',
  local_host_name: 'TANAABAGENTBOX1',
  macos_identity_ok: '1',
  headless_power_ok: '1',
  network_time_ok: '1',
  restart_freeze_ok: '1',
  remote_login_ok: '1',
  ssh_access_group_exists_ok: '1',
  ssh_access_group: 'com.apple.access_ssh',
  ssh_access_admin_user_ok: '1',
  ssh_access_openclaw_user_ok: '1',
  ssh_hardening_expected: '1',
  ssh_hardening_ok: '1',
  admin_user: 'pirog',
  openclaw_user: 'emori',
  openclaw_user_exists_ok: '1',
  openclaw_user_home_ok: '1',
  openclaw_user_non_admin_ok: '1',
  openclaw_user_ok: '1',
  openclaw_autologin_expected: '1',
  openclaw_autologin_ok: '1',
  brewgroup_enabled: '0',
  trusted_brewgroup_enabled: '0',
  homebrew_login_path_bin_ok: '1',
  homebrew_login_path_sbin_ok: '1',
  homebrew_login_path_file_ok: '1',
  openclaw_cli_ok: '1',
  node_cli_ok: '1',
  ripgrep_ok: '1',
  openclaw_service_mode: 'system',
  openclaw_gateway_label: 'dev.tanaab.agentbox.openclaw-gateway',
  openclaw_gateway_bind: 'loopback',
  openclaw_gateway_port: '18789',
  openclaw_gateway_tailscale_mode: 'off',
  openclaw_gateway_launchd_loaded_ok: '1',
  openclaw_gateway_launchd_running_ok: '1',
  openclaw_gateway_log_permissions_ok: '1',
  openclaw_gateway_status_ok: '1',
  openclaw_gateway_ok: '1',
  tailscale_expected: '0',
  tailscale_firewall_warning: 'skipped',
  health_launchd_loaded_ok: '1',
  agentbox_ok: '1',
};

describe('skills/agentbox-doctor/scripts/check-host-lib', () => {
  it('should keep the latest key and preserve equals signs in values', () => {
    const values = parseHealthReport('agentbox_ok=0\nignored line\nnote=a=b\n---\nagentbox_ok=1\n');

    assert.deepEqual(values, { agentbox_ok: '1', note: 'a=b' });
  });

  it('should group a healthy base report without activating Tailscale checks', () => {
    const report = evaluateHealth(healthyValues, {
      healthScript: '/opt/tanaab/agentbox/bin/health.sh',
      pluginVersion: '1.0.0-beta.6',
    });
    const tailscaleGroup = report.groups.find((group) => group.id === 'tailscale');

    assert.equal(report.status, 'healthy');
    assert.equal(report.issues.length, 0);
    assert.equal(tailscaleGroup?.status, 'healthy');
    assert.equal(tailscaleGroup?.passed, 0);
  });

  it('should surface a conditional Tailscale Serve failure with a rendered repair', () => {
    const values = {
      ...healthyValues,
      openclaw_gateway_tailscale_mode: 'serve',
      tailscale_expected: '1',
      tailscaled_launchd_loaded_ok: '1',
      tailscaled_launchd_running_ok: '1',
      tailscaled_homebrew_launchd_absent_ok: '1',
      tailscaled_homebrew_user_launchd_absent_ok: '1',
      tailscaled_official_launchd_absent_ok: '1',
      tailscaled_state_file_ok: '1',
      tailscale_operator_ok: '1',
      tailscale_magicdns_enabled: '1',
      tailscale_magicdns_resolver_ok: '0',
      tailscale_magicdns_resolver_path: '/etc/resolver/example.ts.net',
      tailscale_https_certificates_enabled: '1',
      openclaw_gateway_tailscale_serve_route_ok: '1',
      tailscale_ok: '1',
      agentbox_ok: '0',
    };
    const report = evaluateHealth(values, { pluginVersion: '1.0.0-beta.6' });
    const issue = report.issues.find(
      (candidate) => candidate.key === 'tailscale_magicdns_resolver_ok',
    );

    assert.equal(report.status, 'unhealthy');
    assert.equal(report.groups.find((group) => group.id === 'tailscale')?.status, 'unhealthy');
    assert.match(issue?.remediation.command || '', /'\/etc\/resolver\/example[.]ts[.]net'/);
    assert.doesNotMatch(issue?.remediation.command || '', /\{\{/);
  });

  it('should not emit a partial command when a report value is missing', () => {
    const report = evaluateHealth({
      ...healthyValues,
      expected_hostname: '',
      macos_identity_ok: '0',
      agentbox_ok: '0',
    });
    const issue = report.issues.find((candidate) => candidate.key === 'macos_identity_ok');

    assert.deepEqual(
      {
        kind: issue?.remediation.kind,
        command: issue?.remediation.command,
        requiresConfirmation: issue?.remediation.requiresConfirmation,
      },
      { kind: 'investigate', command: null, requiresConfirmation: false },
    );
  });

  it('should warn when plugin and installed host versions differ', () => {
    const report = evaluateHealth(healthyValues, { pluginVersion: '1.0.0-beta.7' });

    assert.equal(report.status, 'warning');
    assert.ok(report.warnings.some((warning) => warning.key === 'agentbox_version_mismatch'));
  });

  it('should treat a release tag prefix as the same plugin and host version', () => {
    const report = evaluateHealth(
      { ...healthyValues, agentbox_version: 'v1.0.0-beta.6' },
      { pluginVersion: '1.0.0-beta.6' },
    );

    assert.equal(report.status, 'healthy');
    assert.ok(!report.warnings.some((warning) => warning.key === 'agentbox_version_mismatch'));
  });

  it('should not recommend a system launchd repair for native user service mode', () => {
    const report = evaluateHealth({
      ...healthyValues,
      openclaw_service_mode: 'user',
      openclaw_gateway_status_ok: '0',
      openclaw_gateway_ok: '0',
      agentbox_ok: '0',
    });
    const issue = report.issues.find((candidate) => candidate.key === 'openclaw_gateway_status_ok');

    assert.deepEqual(
      {
        kind: issue?.remediation.kind,
        command: issue?.remediation.command,
        requiresConfirmation: issue?.remediation.requiresConfirmation,
      },
      { kind: 'reconcile', command: null, requiresConfirmation: false },
    );
  });

  it('should attach the configured default installer only to reconcile remediation', () => {
    const installer = {
      status: 'available',
      default: 'source',
      installation: {
        key: 'source',
        kind: 'source',
        path: '/Users/example/agentbox/macos.sh',
        version: 'v1.0.0-beta.6',
      },
    };
    const report = evaluateHealth(
      {
        ...healthyValues,
        openclaw_service_mode: 'user',
        openclaw_gateway_status_ok: '0',
        openclaw_gateway_ok: '0',
        agentbox_ok: '0',
      },
      { installer },
    );
    const issue = report.issues.find((candidate) => candidate.key === 'openclaw_gateway_status_ok');

    assert.deepEqual(issue?.remediation.installer, {
      key: 'source',
      path: '/Users/example/agentbox/macos.sh',
      version: 'v1.0.0-beta.6',
    });
    assert.deepEqual(issue?.remediation.handoff, {
      skill: '$tanaab-agentbox',
      installationKey: 'source',
    });
    assert.equal(report.source.installer.key, 'source');
  });

  it('should hand an uninstalled host to the primary agentbox workflow', () => {
    const report = unavailableReport(
      'not_installed',
      'The installed agentbox health script was not found.',
    );

    assert.deepEqual(report.error.handoff, {
      skill: '$tanaab-agentbox',
      intent: 'bootstrap_or_reconcile',
    });
  });

  it('should warn when the configured default would change the installed host version', () => {
    const report = evaluateHealth(healthyValues, {
      installer: {
        status: 'available',
        default: 'source',
        installation: {
          key: 'source',
          kind: 'source',
          path: '/Users/example/agentbox/macos.sh',
          version: 'v1.0.0-beta.7',
        },
      },
    });

    assert.equal(report.status, 'warning');
    assert.ok(
      report.warnings.some((warning) => warning.key === 'agentbox_installer_version_mismatch'),
    );
  });

  it('should hand unavailable installer state to the installer workflow', () => {
    const report = evaluateHealth(healthyValues, {
      installer: {
        status: 'invalid_config',
        error: { detail: 'could not parse config.json' },
      },
    });
    const warning = report.warnings.find(
      (candidate) => candidate.key === 'agentbox_installer_unavailable',
    );

    assert.deepEqual(warning?.remediation.handoff, {
      skill: '$tanaab-agentbox-installer',
      intent: 'repair_installation_state',
      status: 'invalid_config',
    });
  });

  it('should not hide health-contract drift behind a healthy catalog', () => {
    const report = evaluateHealth(
      { ...healthyValues, agentbox_ok: '0' },
      { pluginVersion: '1.0.0-beta.6' },
    );

    assert.equal(report.status, 'unhealthy');
    assert.ok(report.issues.some((issue) => issue.key === 'health_contract_mismatch'));
  });

  it('should not report healthy when an aggregate fails without a leaf failure', () => {
    const report = evaluateHealth(
      {
        ...healthyValues,
        openclaw_gateway_ok: '0',
        agentbox_ok: '0',
      },
      { pluginVersion: '1.0.0-beta.6' },
    );

    assert.equal(report.status, 'unhealthy');
    assert.equal(report.ok, false);
    assert.equal(report.summary.failed, 1);
    assert.equal(report.groups.find((group) => group.id === 'openclaw')?.status, 'unhealthy');
    assert.ok(report.issues.some((issue) => issue.key === 'health_contract_mismatch'));
  });

  it('should cover every health check marked required by the installed contract source', () => {
    const healthSource = readFileSync(new URL('../bin/health.sh', import.meta.url), 'utf8');
    const requiredKeys = [...healthSource.matchAll(/mark_required +([a-z][a-z0-9_]*)/g)].map(
      (match) => match[1],
    );
    const catalogKeys = new Set(
      checkCatalog.groups.flatMap((group) => group.checks.map((check) => check.key)),
    );

    assert.deepEqual(
      [...new Set(requiredKeys)].filter((key) => !catalogKeys.has(key)),
      [],
    );
  });

  it('should provide remediation metadata for every surfaced leaf check', () => {
    const missingRemediations = checkCatalog.groups
      .flatMap((group) => group.checks)
      .filter((check) => check.issue !== false && !remediationCatalog[check.key])
      .map((check) => check.key);

    assert.deepEqual(missingRemediations, []);
  });

  it('should use the health-reported Homebrew prefix for formula commands', () => {
    assert.equal(
      remediationCatalog.openclaw_cli_ok.command,
      '{{brew_prefix}}/bin/brew reinstall openclaw-cli',
    );
    assert.equal(remediationCatalog.node_cli_ok.command, '{{brew_prefix}}/bin/brew install node');
    assert.equal(remediationCatalog.ripgrep_ok.command, '{{brew_prefix}}/bin/brew install ripgrep');
    assert.equal(
      remediationCatalog.tailscale_operator_ok.command,
      'sudo {{brew_prefix}}/bin/tailscale set --operator={{openclaw_user}}',
    );
  });

  it('should remove persistent Homebrew tailscaled launchd conflicts', () => {
    const report = evaluateHealth({
      ...healthyValues,
      tailscale_expected: '1',
      tailscaled_launchd_loaded_ok: '1',
      tailscaled_launchd_running_ok: '1',
      tailscaled_homebrew_launchd_absent_ok: '0',
      tailscaled_homebrew_user_launchd_absent_ok: '0',
      tailscaled_official_launchd_absent_ok: '1',
      tailscaled_state_file_ok: '1',
      tailscale_operator_ok: '1',
      tailscale_ok: '0',
      agentbox_ok: '0',
    });
    const systemIssue = report.issues.find(
      (issue) => issue.key === 'tailscaled_homebrew_launchd_absent_ok',
    );
    const userIssue = report.issues.find(
      (issue) => issue.key === 'tailscaled_homebrew_user_launchd_absent_ok',
    );

    assert.match(
      systemIssue?.remediation.command || '',
      /rm -f \/Library\/LaunchDaemons\/homebrew[.]mxcl[.]tailscale[.]plist/,
    );
    assert.match(userIssue?.remediation.command || '', /admin_user='pirog'/);
    assert.match(userIssue?.remediation.command || '', /NFSHomeDirectory/);
    assert.match(
      userIssue?.remediation.command || '',
      /rm -f .*Library\/LaunchAgents\/homebrew[.]mxcl[.]tailscale[.]plist/,
    );
    assert.doesNotMatch(userIssue?.remediation.command || '', /\{\{/);
  });

  it('should keep every remediation command syntactically valid', () => {
    for (const [key, remediation] of Object.entries(remediationCatalog)) {
      const candidates = [remediation, ...(remediation.variants || [])];
      for (const candidate of candidates) {
        if (!candidate.command) continue;
        const command = candidate.command.replace(/\{\{[a-z0-9_]+\}\}/g, "'value'");
        const result = spawnSync('/bin/bash', ['-n', '-c', command], { encoding: 'utf8' });
        if (result.status !== 0) throw new Error(`${key}: ${result.stderr}`);
      }
    }
  });
});
