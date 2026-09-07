// Mihomo Party subscription override for the repository's Mihomo layout.

const DIRECT_PROXY_NAME = "直连";
const DEFAULT_GROUP_NAME = "默认";
const OPENAI_GROUP_NAME = "OpenAI";
const GOOGLE_GROUP_NAME = "Google";
const DNS_GROUP_NAME = "dns";
const AUTO_GROUP_NAME = "自动选择";
const ALL_GROUP_NAME = "全部节点";
const OTHER_REGION_GROUP_NAME = "其它地区";

const REGION_DEFINITIONS = [
    {
        name: "香港",
        nodePattern: /(?:香港|港|hk|hong\s*kong|hongkong|🇭🇰)/i,
        providerFilter: "(?i)港|hk|hongkong|hong kong|🇭🇰",
    },
    {
        name: "台湾",
        nodePattern: /(?:台湾|台|tw|taiwan|🇹🇼)/i,
        providerFilter: "(?i)台|tw|taiwan|🇹🇼",
    },
    {
        name: "日本",
        nodePattern: /(?:日本|日|jp|japan|tokyo|osaka|🇯🇵)/i,
        providerFilter: "(?i)日|jp|japan|tokyo|osaka|🇯🇵",
    },
    {
        name: "新加坡",
        nodePattern: /(?:新加坡|狮城|新|sg|singapore|🇸🇬)/i,
        providerFilter: "(?i)新|sg|singapore|🇸🇬",
    },
    {
        name: "美国",
        nodePattern: /(?:美国|美|usa|united\s*states|\bus(?:[_ -]?\d+)?\b|🇺🇸)/i,
        providerFilter: "(?i)美|USA|🇺🇸|United\\s*States|\\bUS(\\b|[_\\d])",
    },
];

const REGION_NAMES = REGION_DEFINITIONS.map((region) => region.name);
const EXCLUDED_NODE_TERMS =
    "剩余|到期|主页|官网|游戏|关注|网站|地址|有效|网址|禁止|邮箱|发布|客服|订阅|节点|问题|联系|\\bGB\\b|Traffic|Expire|Premium|频道|ISP|流量|重置";
const ALL_REGION_TERMS = REGION_DEFINITIONS
    .map((region) => region.providerFilter.replace(/^\(\?i\)/, ""))
    .join("|");
const OTHER_REGION_PROVIDER_FILTER =
    `(?i)^(?!.*(?:${ALL_REGION_TERMS}|${EXCLUDED_NODE_TERMS})).*$`;
const PROVIDER_EXCLUDE_FILTER = `(?i)(?:${EXCLUDED_NODE_TERMS})`;

const BUILTIN_RULE_PROVIDERS = {
    openai: {
        type: "http",
        behavior: "domain",
        format: "yaml",
        interval: 86400,
        url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/openai.yaml",
        path: "./rule-providers/openai.yaml",
    },
    google: {
        type: "http",
        behavior: "domain",
        format: "yaml",
        interval: 86400,
        url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.yaml",
        path: "./rule-providers/google.yaml",
    },
    googleIp: {
        type: "http",
        behavior: "ipcidr",
        format: "yaml",
        interval: 86400,
        url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/google.yaml",
        path: "./rule-providers/google_ip.yaml",
    },
};

function main(config) {
    if (!config || typeof config !== "object") return config;

    const proxyContext = prepareProxies(config);
    const groupNames = ensureProxyGroups(config, proxyContext);
    ensureRules(config, groupNames);
    return config;
}

function prepareProxies(config) {
    const proxies = Array.isArray(config.proxies) ? [...config.proxies] : [];
    const proxyNames = new Set(
        proxies
            .map(getProxyName)
            .filter((name) => typeof name === "string" && name.length > 0),
    );

    if (!proxyNames.has(DIRECT_PROXY_NAME)) {
        proxies.push({ name: DIRECT_PROXY_NAME, type: "direct", udp: true });
    }
    config.proxies = proxies;

    const nodeNames = unique(
        proxies
            .map(getProxyName)
            .filter((name) => isNodeName(name)),
    );

    return {
        nodeNames,
        useProxyProviders:
            nodeNames.length === 0 && hasProxyProviders(config),
    };
}

function ensureProxyGroups(config, context) {
    const groups = Array.isArray(config["proxy-groups"])
        ? [...config["proxy-groups"]]
        : [];
    const selectorProxies = [
        DEFAULT_GROUP_NAME,
        ...REGION_NAMES,
        OTHER_REGION_GROUP_NAME,
        ALL_GROUP_NAME,
        AUTO_GROUP_NAME,
        DIRECT_PROXY_NAME,
    ];
    const defaultProxies = [
        AUTO_GROUP_NAME,
        DIRECT_PROXY_NAME,
        ...REGION_NAMES,
        OTHER_REGION_GROUP_NAME,
        ALL_GROUP_NAME,
    ];

    const defaultName = upsertSelectGroup(
        groups,
        [DEFAULT_GROUP_NAME, "default"],
        DEFAULT_GROUP_NAME,
        defaultProxies,
    );
    const dnsName = upsertSelectGroup(
        groups,
        [DNS_GROUP_NAME, "DNS"],
        DNS_GROUP_NAME,
        [
            AUTO_GROUP_NAME,
            defaultName,
            ...REGION_NAMES,
            OTHER_REGION_GROUP_NAME,
            ALL_GROUP_NAME,
        ],
    );
    const openaiName = upsertSelectGroup(
        groups,
        [OPENAI_GROUP_NAME, "openai"],
        OPENAI_GROUP_NAME,
        selectorProxies,
    );
    const googleName = upsertSelectGroup(
        groups,
        [GOOGLE_GROUP_NAME, "google"],
        GOOGLE_GROUP_NAME,
        selectorProxies,
    );

    for (const region of REGION_DEFINITIONS) {
        appendGroupIfMissing(
            groups,
            context.useProxyProviders
                ? {
                      name: region.name,
                      type: "select",
                      "include-all-providers": true,
                      "exclude-filter": PROVIDER_EXCLUDE_FILTER,
                      filter: region.providerFilter,
                  }
                : {
                      name: region.name,
                      type: "select",
                      proxies: matchingNodes(context.nodeNames, region.nodePattern),
                  },
        );
    }

    appendGroupIfMissing(
        groups,
        context.useProxyProviders
            ? {
                  name: OTHER_REGION_GROUP_NAME,
                  type: "select",
                  "include-all-providers": true,
                  "exclude-filter": PROVIDER_EXCLUDE_FILTER,
                  filter: OTHER_REGION_PROVIDER_FILTER,
              }
            : {
                  name: OTHER_REGION_GROUP_NAME,
                  type: "select",
                  proxies: matchingOtherNodes(context.nodeNames),
              },
    );

    appendGroupIfMissing(
        groups,
        context.useProxyProviders
            ? {
                  name: ALL_GROUP_NAME,
                  type: "select",
                  "include-all-providers": true,
                  "exclude-filter": PROVIDER_EXCLUDE_FILTER,
              }
            : {
                  name: ALL_GROUP_NAME,
                  type: "select",
                  proxies: fallbackNodes(context.nodeNames),
              },
    );
    appendGroupIfMissing(
        groups,
        context.useProxyProviders
            ? {
                  name: AUTO_GROUP_NAME,
                  type: "url-test",
                  "include-all-providers": true,
                  "exclude-filter": PROVIDER_EXCLUDE_FILTER,
                  url: "https://www.gstatic.com/generate_204",
                  interval: 300,
                  tolerance: 10,
              }
            : {
                  name: AUTO_GROUP_NAME,
                  type: "url-test",
                  proxies: fallbackNodes(context.nodeNames),
                  url: "https://www.gstatic.com/generate_204",
                  interval: 300,
                  tolerance: 10,
              },
    );

    config["proxy-groups"] = groups;
    return {
        default: defaultName,
        dns: dnsName,
        openai: openaiName,
        google: googleName,
    };
}

function ensureRules(config, groupNames) {
    const ruleProviders = isPlainObject(config["rule-providers"])
        ? { ...config["rule-providers"] }
        : {};
    const rules = Array.isArray(config.rules) ? [...config.rules] : [];

    ensureRuleSetRoute(
        ruleProviders,
        rules,
        ["default", "default_domain"],
        groupNames.default,
    );
    ensureRuleSetRoute(
        ruleProviders,
        rules,
        ["openai", "openai_domain"],
        groupNames.openai,
        BUILTIN_RULE_PROVIDERS.openai,
        "openai",
    );
    ensureRuleSetRoute(
        ruleProviders,
        rules,
        ["google", "google_domain"],
        groupNames.google,
        BUILTIN_RULE_PROVIDERS.google,
        "google",
    );
    ensureRuleSetRoute(
        ruleProviders,
        rules,
        ["google_ip"],
        groupNames.google,
        BUILTIN_RULE_PROVIDERS.googleIp,
        "google_ip",
    );

    if (!rules.some(isMatchRule)) {
        rules.push(`MATCH,${groupNames.default}`);
    }

    config["rule-providers"] = ruleProviders;
    config.rules = rules;
}

function ensureRuleSetRoute(
    providers,
    rules,
    aliases,
    targetGroup,
    builtinProvider,
    fallbackProviderName,
) {
    let providerKeys = findProviderKeys(providers, aliases);
    if (providerKeys.length === 0 && builtinProvider) {
        providers[fallbackProviderName] = { ...builtinProvider };
        providerKeys = [fallbackProviderName];
    }

    for (const providerKey of providerKeys) {
        const ruleIndex = findRuleSetRule(rules, providerKey);
        if (ruleIndex === -1) {
            rules.unshift(`RULE-SET,${providerKey},${targetGroup}`);
            continue;
        }

        const parts = rules[ruleIndex].split(",");
        parts[2] = targetGroup;
        rules[ruleIndex] = parts.join(",");
    }
}

function upsertSelectGroup(groups, aliases, fallbackName, proxies) {
    const index = findGroupIndex(groups, aliases);
    if (index === -1) {
        groups.push({ name: fallbackName, type: "select", proxies: unique(proxies) });
        return fallbackName;
    }

    const existing = groups[index];
    const updated = { ...existing, type: "select", proxies: unique(proxies) };
    delete updated.filter;
    delete updated["include-all-providers"];
    groups[index] = updated;
    return existing.name;
}

function appendGroupIfMissing(groups, group) {
    if (findGroupIndex(groups, [group.name]) === -1) {
        groups.push(group);
    }
}

function findGroupIndex(groups, aliases) {
    const normalizedAliases = aliases.map((alias) => alias.toLowerCase());
    return groups.findIndex(
        (group) =>
            group &&
            typeof group.name === "string" &&
            normalizedAliases.includes(group.name.toLowerCase()),
    );
}

function matchingNodes(nodeNames, pattern) {
    const matches = nodeNames.filter((name) => pattern.test(name));
    return fallbackNodes(matches);
}

function matchingOtherNodes(nodeNames) {
    const matches = nodeNames.filter(
        (name) => !REGION_DEFINITIONS.some((region) => region.nodePattern.test(name)),
    );
    return fallbackNodes(matches);
}

function fallbackNodes(nodes) {
    return nodes.length > 0 ? unique(nodes) : [DIRECT_PROXY_NAME];
}

function findProviderKeys(providers, aliases) {
    const normalizedAliases = new Set(aliases.map((alias) => alias.toLowerCase()));
    return Object.keys(providers).filter((key) =>
        normalizedAliases.has(key.toLowerCase()),
    );
}

function findRuleSetRule(rules, providerKey) {
    const normalizedProviderKey = providerKey.toLowerCase();
    return rules.findIndex((rule) => {
        if (typeof rule !== "string") return false;
        const parts = rule.split(",");
        return (
            parts.length >= 3 &&
            parts[0].trim().toLowerCase() === "rule-set" &&
            parts[1].trim().toLowerCase() === normalizedProviderKey
        );
    });
}

function isMatchRule(rule) {
    return typeof rule === "string" && rule.split(",")[0].trim().toLowerCase() === "match";
}

function hasProxyProviders(config) {
    return isPlainObject(config["proxy-providers"])
        && Object.keys(config["proxy-providers"]).length > 0;
}

function getProxyName(proxy) {
    if (typeof proxy === "string") return proxy;
    return proxy && typeof proxy.name === "string" ? proxy.name : null;
}

function isNodeName(name) {
    if (typeof name !== "string" || name.length === 0) return false;
    if (["DIRECT", "REJECT", "PASS", "COMPATIBLE", DIRECT_PROXY_NAME].includes(name)) {
        return false;
    }
    return !new RegExp(EXCLUDED_NODE_TERMS, "i").test(name);
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function unique(values) {
    return [...new Set(values)];
}
