import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

import { evaluateHealth, parseHealthReport } from './check-host-lib.js';

const checkCatalog = JSON.parse(
  readFileSync(new URL('../references/checks.json', import.meta.url), 'utf8'),
);
const remediationCatalog = JSON.parse(
  readFileSync(new URL('../references/remediations.json', import.meta.url), 'utf8'),
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

describe('parseHealthReport', () => {
  test('keeps the latest key and preserves equals signs in values', () => {
    const values = parseHealthReport('agentbox_ok=0\nignored line\nnote=a=b\n---\nagentbox_ok=1\n');

    expect(values).toEqual({ agentbox_ok: '1', note: 'a=b' });
  });
});

describe('evaluateHealth', () => {
  test('groups a healthy base report without activating Tailscale checks', () => {
    const report = evaluateHealth(healthyValues, {
      healthScript: '/opt/tanaab/agentbox/bin/health.sh',
      pluginVersion: '1.0.0-beta.6',
    });

    expect(report.status).toBe('healthy');
    expect(report.issues).toHaveLength(0);
    expect(report.groups.find((group) => group.id === 'tailscale')).toMatchObject({
      status: 'healthy',
      passed: 0,
    });
  });

  test('surfaces a conditional Tailscale Serve failure with a rendered repair', () => {
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

    expect(report.status).toBe('unhealthy');
    expect(report.groups.find((group) => group.id === 'tailscale').status).toBe('unhealthy');
    expect(issue.remediation.command).toContain("'/etc/resolver/example.ts.net'");
    expect(issue.remediation.command).not.toContain('{{');
  });

  test('does not emit a partial command when a report value is missing', () => {
    const values = {
      ...healthyValues,
      expected_hostname: '',
      macos_identity_ok: '0',
      agentbox_ok: '0',
    };
    const report = evaluateHealth(values);
    const issue = report.issues.find((candidate) => candidate.key === 'macos_identity_ok');

    expect(issue.remediation).toMatchObject({
      kind: 'investigate',
      command: null,
      requiresConfirmation: false,
    });
  });

  test('warns when plugin and installed host versions differ', () => {
    const report = evaluateHealth(healthyValues, { pluginVersion: '1.0.0-beta.7' });

    expect(report.status).toBe('warning');
    expect(report.warnings.map((warning) => warning.key)).toContain('agentbox_version_mismatch');
  });

  test('does not recommend a system launchd repair for native user service mode', () => {
    const report = evaluateHealth({
      ...healthyValues,
      openclaw_service_mode: 'user',
      openclaw_gateway_status_ok: '0',
      openclaw_gateway_ok: '0',
      agentbox_ok: '0',
    });
    const issue = report.issues.find((candidate) => candidate.key === 'openclaw_gateway_status_ok');

    expect(issue.remediation).toMatchObject({
      kind: 'reconcile',
      command: null,
      requiresConfirmation: false,
    });
  });

  test('does not hide health-contract drift behind a healthy catalog', () => {
    const report = evaluateHealth(
      { ...healthyValues, agentbox_ok: '0' },
      { pluginVersion: '1.0.0-beta.6' },
    );

    expect(report.status).toBe('unhealthy');
    expect(report.issues.map((issue) => issue.key)).toContain('health_contract_mismatch');
  });
});

describe('doctor catalogs', () => {
  test('cover every health check marked required by the installed contract source', () => {
    const healthSource = readFileSync(new URL('../../../bin/health.sh', import.meta.url), 'utf8');
    const requiredKeys = [...healthSource.matchAll(/mark_required +([a-z][a-z0-9_]*)/g)].map(
      (match) => match[1],
    );
    const catalogKeys = new Set(
      checkCatalog.groups.flatMap((group) => group.checks.map((check) => check.key)),
    );

    expect([...new Set(requiredKeys)].filter((key) => !catalogKeys.has(key))).toEqual([]);
  });

  test('provide remediation metadata for every surfaced leaf check', () => {
    const missingRemediations = checkCatalog.groups
      .flatMap((group) => group.checks)
      .filter((check) => check.issue !== false && !remediationCatalog[check.key])
      .map((check) => check.key);

    expect(missingRemediations).toEqual([]);
  });

  test('keep every remediation command syntactically valid', () => {
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
