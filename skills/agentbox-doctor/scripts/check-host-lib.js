import { readFileSync } from 'node:fs';

const checkCatalog = JSON.parse(
  readFileSync(new URL('../references/checks.json', import.meta.url), 'utf8'),
);
const remediationCatalog = JSON.parse(
  readFileSync(new URL('../references/remediations.json', import.meta.url), 'utf8'),
);

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

function conditionsMatch(conditions = [], values) {
  return conditions.every((condition) => values[condition.key] === condition.equals);
}

function renderCommand(template, values) {
  let missingValue = false;
  const command = template.replace(/\{\{([a-z0-9_]+)\}\}/g, (_match, key) => {
    const value = values[key];
    if (value === undefined || value === '' || value === 'skipped') {
      missingValue = true;
      return `<missing:${key}>`;
    }
    return shellQuote(value);
  });

  return missingValue ? null : command;
}

function remediationFor(key, values, installer) {
  const remediation = remediationCatalog[key];
  if (!remediation) {
    return {
      kind: 'investigate',
      summary:
        'Inspect the matching check in the installed health script; this plugin version has no focused remediation registered.',
      command: null,
      requiresConfirmation: false,
    };
  }

  const variant = remediation.variants?.find((candidate) =>
    conditionsMatch(candidate.when, values),
  );
  const selected = variant ? { ...remediation, ...variant } : remediation;
  const command = selected.command ? renderCommand(selected.command, values) : null;
  const missingCommandInput = Boolean(selected.command) && !command;

  const result = {
    kind: missingCommandInput ? 'investigate' : selected.kind,
    summary: missingCommandInput
      ? `${selected.summary} The installed report omitted a value required to render the command.`
      : selected.summary,
    command,
    requiresConfirmation: Boolean(command),
  };
  if (result.kind === 'reconcile') {
    result.handoff = {
      skill: '$tanaab-agentbox',
      installationKey: installer?.status === 'available' ? installer.installation.key : null,
    };
    if (installer?.status === 'available') {
      result.installer = {
        key: installer.installation.key,
        path: installer.installation.path,
        version: installer.installation.version,
      };
    }
  }
  return result;
}

function addGroupWarning(groups, groupId) {
  const group = groups.find((candidate) => candidate.id === groupId);
  if (!group) return;
  group.warnings += 1;
  if (group.status === 'healthy') group.status = 'warning';
}

export function parseHealthReport(report) {
  const values = {};

  for (const rawLine of report.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line === '---') continue;

    const match = line.match(/^([a-z0-9_]+)=(.*)$/);
    if (!match) continue;
    values[match[1]] = match[2];
  }

  return values;
}

export function evaluateHealth(values, options = {}) {
  const groups = checkCatalog.groups.map((groupDefinition) => {
    const checks = groupDefinition.checks.map((checkDefinition) => {
      const active = conditionsMatch(checkDefinition.when, values);
      const value = values[checkDefinition.key];
      const status = !active ? 'skipped' : value === '1' ? 'healthy' : 'unhealthy';

      return {
        key: checkDefinition.key,
        label: checkDefinition.label,
        status,
        value: value ?? null,
        active,
        issue: checkDefinition.issue !== false,
      };
    });
    const activeChecks = checks.filter((check) => check.active);
    const failed = activeChecks.filter((check) => check.status === 'unhealthy').length;
    const passed = activeChecks.length - failed;

    return {
      id: groupDefinition.id,
      label: groupDefinition.label,
      status: failed > 0 ? 'unhealthy' : 'healthy',
      passed,
      failed,
      skipped: checks.length - activeChecks.length,
      warnings: 0,
      checks,
    };
  });

  const issues = groups.flatMap((group) =>
    group.checks
      .filter((check) => check.active && check.status === 'unhealthy' && check.issue)
      .map((check) => ({
        severity: 'failure',
        key: check.key,
        label: check.label,
        group: group.id,
        detail:
          check.value === null
            ? `The installed health report omitted ${check.key}.`
            : `${check.label} reported ${check.value}.`,
        remediation: remediationFor(check.key, values, options.installer),
      })),
  );
  const warnings = [];
  const failedChecks = groups.reduce((total, group) => total + group.failed, 0);
  const passedChecks = groups.reduce((total, group) => total + group.passed, 0);
  const skippedChecks = groups.reduce((total, group) => total + group.skipped, 0);
  const unexplainedAggregateFailures = groups.flatMap((group) => {
    const failed = group.checks.filter((check) => check.active && check.status === 'unhealthy');
    if (failed.some((check) => check.issue)) return [];
    return failed.filter((check) => !check.issue);
  });

  if (values.tailscale_firewall_warning === '1') {
    warnings.push({
      severity: 'warning',
      key: 'tailscale_firewall_warning',
      label: 'macOS application firewall',
      group: 'tailscale',
      detail: 'The application firewall is enabled while Tailscale Serve is configured.',
      remediation: remediationFor('tailscale_firewall_warning', values, options.installer),
    });
    addGroupWarning(groups, 'tailscale');
  }

  const installedVersion = values.agentbox_version || null;
  const pluginVersion = options.pluginVersion || null;
  if (
    installedVersion &&
    pluginVersion &&
    normalizeVersion(installedVersion) !== normalizeVersion(pluginVersion)
  ) {
    warnings.push({
      severity: 'warning',
      key: 'agentbox_version_mismatch',
      label: 'Plugin and host versions differ',
      group: 'monitoring',
      detail: `The host reports agentbox ${installedVersion}, while this plugin is ${pluginVersion}.`,
      remediation: {
        kind: 'manual',
        summary:
          'Align the plugin and installed host versions before relying on version-specific remediation details.',
        command: null,
        requiresConfirmation: false,
      },
    });
    addGroupWarning(groups, 'monitoring');
  }

  const installer = options.installer || null;
  if (installer?.status === 'available') {
    const installerVersion = installer.installation.version;
    if (
      installedVersion &&
      installerVersion &&
      normalizeVersion(installedVersion) !== normalizeVersion(installerVersion)
    ) {
      warnings.push({
        severity: 'warning',
        key: 'agentbox_installer_version_mismatch',
        label: 'Default installer and host versions differ',
        group: 'monitoring',
        detail: `The installed host reports agentbox ${installedVersion}, while the configured ${installer.installation.key} installer is ${installerVersion}.`,
        remediation: {
          kind: 'manual',
          summary:
            'Confirm whether the next reconciliation should preserve the installed version or intentionally update the host.',
          command: null,
          requiresConfirmation: false,
        },
      });
      addGroupWarning(groups, 'monitoring');
    }
  } else if (installer && !['unconfigured'].includes(installer.status)) {
    warnings.push({
      severity: 'warning',
      key: 'agentbox_installer_unavailable',
      label: 'Configured installer unavailable',
      group: 'monitoring',
      detail:
        installer.error?.detail || 'The configured default agentbox installer is unavailable.',
      remediation: {
        kind: 'manual',
        summary:
          'Repair the agentbox installation state before using installer-backed remediation.',
        command: null,
        requiresConfirmation: false,
        handoff: {
          skill: '$tanaab-agentbox-installer',
          intent: 'repair_installation_state',
          status: installer.status,
        },
      },
    });
    addGroupWarning(groups, 'monitoring');
  }

  const aggregateHealthy = values.agentbox_ok === '1';
  const catalogHealthy = failedChecks === 0;
  let contractMismatchDetail = null;
  if (values.agentbox_ok === undefined) {
    contractMismatchDetail = 'The installed report omitted agentbox_ok.';
  } else if (aggregateHealthy !== catalogHealthy) {
    contractMismatchDetail = `The installed aggregate is ${values.agentbox_ok}, but the plugin catalog found ${failedChecks} failing checks.`;
  } else if (unexplainedAggregateFailures.length > 0) {
    contractMismatchDetail = `The plugin catalog found failing aggregate checks without failing leaf checks: ${unexplainedAggregateFailures
      .map((check) => check.key)
      .join(', ')}.`;
  }
  if (contractMismatchDetail) {
    issues.push({
      severity: 'failure',
      key: 'health_contract_mismatch',
      label: 'Health contract mismatch',
      group: 'monitoring',
      detail: contractMismatchDetail,
      remediation: {
        kind: 'investigate',
        summary:
          'Compare this plugin version with the installed health script before interpreting unmapped checks or changed conditions.',
        command: null,
        requiresConfirmation: false,
      },
    });
    const monitoring = groups.find((group) => group.id === 'monitoring');
    if (monitoring) monitoring.status = 'unhealthy';
  }

  const status =
    failedChecks > 0 || issues.length > 0
      ? 'unhealthy'
      : warnings.length > 0
        ? 'warning'
        : 'healthy';

  return {
    schemaVersion: 1,
    status,
    ok: status !== 'unhealthy',
    source: {
      healthScript: options.healthScript || null,
      healthTimestamp: values.timestamp || null,
      installedVersion,
      pluginVersion,
      installer:
        installer?.status === 'available'
          ? {
              status: installer.status,
              default: installer.default,
              key: installer.installation.key,
              kind: installer.installation.kind,
              path: installer.installation.path,
              version: installer.installation.version,
            }
          : installer
            ? { status: installer.status }
            : null,
    },
    summary: {
      groups: groups.length,
      passed: passedChecks,
      failed: failedChecks,
      skipped: skippedChecks,
      warnings: warnings.length,
    },
    groups,
    issues,
    warnings,
    facts: {
      host: {
        expectedHostname: values.expected_hostname || null,
        computerName: values.computer_name || null,
        hostName: values.host_name || null,
        localHostName: values.local_host_name || null,
        rootDiskAvailableKb: values.root_disk_available_kb || null,
        uptime: values.uptime || null,
      },
      openclaw: {
        user: values.openclaw_user || null,
        gatewayBind: values.openclaw_gateway_bind || null,
        gatewayPort: values.openclaw_gateway_port || null,
        tailscaleMode: values.openclaw_gateway_tailscale_mode || null,
      },
      tailscale: {
        expected: values.tailscale_expected || null,
        backendState: values.tailscale_backend_state || null,
        hostname: values.tailscale_hostname || null,
        ip: values.tailscale_ip || null,
        magicdnsSuffix: values.tailscale_magicdns_suffix || null,
        resolverPath: values.tailscale_magicdns_resolver_path || null,
      },
      security: {
        firewallEnabled: values.firewall_global_enabled || null,
        firewallStealthEnabled: values.firewall_stealth_enabled || null,
        gatekeeper: values.gatekeeper_status || null,
        filevault: values.filevault_status || null,
      },
    },
  };
}

function normalizeVersion(value) {
  return value.replace(/^v/, '');
}

export function unavailableReport(status, detail, options = {}) {
  return {
    schemaVersion: 1,
    status,
    ok: false,
    source: {
      healthScript: options.healthScript || null,
      pluginVersion: options.pluginVersion || null,
    },
    error: {
      detail,
      ...(status === 'not_installed'
        ? {
            handoff: {
              skill: '$tanaab-agentbox',
              intent: 'bootstrap_or_reconcile',
            },
          }
        : {}),
      remediation:
        status === 'authorization_required'
          ? {
              kind: 'command',
              summary: 'Refresh sudo authorization in the current terminal, then rerun the doctor.',
              command: '/usr/bin/sudo -v',
              requiresConfirmation: true,
            }
          : null,
    },
  };
}
