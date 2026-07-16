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

function remediationFor(key, values) {
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

  return {
    kind: missingCommandInput ? 'investigate' : selected.kind,
    summary: missingCommandInput
      ? `${selected.summary} The installed report omitted a value required to render the command.`
      : selected.summary,
    command,
    requiresConfirmation: Boolean(command),
  };
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
        remediation: remediationFor(check.key, values),
      })),
  );
  const warnings = [];
  const failedChecks = groups.reduce((total, group) => total + group.failed, 0);
  const passedChecks = groups.reduce((total, group) => total + group.passed, 0);
  const skippedChecks = groups.reduce((total, group) => total + group.skipped, 0);

  if (values.tailscale_firewall_warning === '1') {
    warnings.push({
      severity: 'warning',
      key: 'tailscale_firewall_warning',
      label: 'macOS application firewall',
      group: 'tailscale',
      detail: 'The application firewall is enabled while Tailscale Serve is configured.',
      remediation: remediationFor('tailscale_firewall_warning', values),
    });
    addGroupWarning(groups, 'tailscale');
  }

  const installedVersion = values.agentbox_version || null;
  const pluginVersion = options.pluginVersion || null;
  if (installedVersion && pluginVersion && installedVersion !== pluginVersion) {
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

  const aggregateHealthy = values.agentbox_ok === '1';
  const catalogHealthy = failedChecks === 0;
  if (values.agentbox_ok === undefined || aggregateHealthy !== catalogHealthy) {
    issues.push({
      severity: 'failure',
      key: 'health_contract_mismatch',
      label: 'Health contract mismatch',
      group: 'monitoring',
      detail:
        values.agentbox_ok === undefined
          ? 'The installed report omitted agentbox_ok.'
          : `The installed aggregate is ${values.agentbox_ok}, but the plugin catalog found ${failedChecks} failing checks.`,
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

  const status = issues.length > 0 ? 'unhealthy' : warnings.length > 0 ? 'warning' : 'healthy';

  return {
    schemaVersion: 1,
    status,
    ok: status !== 'unhealthy',
    source: {
      healthScript: options.healthScript || null,
      healthTimestamp: values.timestamp || null,
      installedVersion,
      pluginVersion,
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
        serviceMode: values.openclaw_service_mode || null,
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
