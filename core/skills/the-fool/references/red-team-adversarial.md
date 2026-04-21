---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/the-fool/references/red-team-adversarial.md
ported-at: 2026-04-17
adapted: true
---

# Red team / adversarial

Red teaming asks: *"If someone wanted to break, exploit, or game this, how
would they do it?"* You adopt the adversary's mindset — not to cause harm,
but to find the weakness before the real adversary does.

Applies beyond security. Competitors, disgruntled users, perverse incentives,
and regulators are all adversarial forces.

## Process

1. **Identify the asset.** What is protected?
2. **Construct adversary personas.** Specific, not generic.
3. **Map attack vectors per persona.**
4. **Assess.** Likelihood × impact.
5. **Design defenses.** Specific countermeasures for the highest-ranked
   vectors.

## Adversary personas

Generic "attackers" produce generic findings. Specific personas produce
actionable insights.

### Persona template

| Field | Description |
|---|---|
| Role | Who |
| Motivation | Why |
| Capability | Resources and skills |
| Access | What they already have |
| Constraints | What limits them |

### Common personas

| Persona | Motivation | Typical vectors |
|---|---|---|
| External attacker | Financial gain, data theft | API exploitation, credential stuffing, injection |
| Competitor | Market advantage | Feature copying, talent poaching, FUD |
| Disgruntled insider | Revenge, financial | Privilege escalation, exfiltration, sabotage |
| Careless user | Accidental | Misconfiguration, weak passwords, sharing creds |
| Regulator | Compliance | Audit findings, data-handling, accessibility gaps |
| Opportunistic gamer | Personal benefit | Loophole exploitation, referral fraud |
| Activist | Ideology | Public embarrassment, leaks, service disruption |

### Domain-specific

| Domain | Key adversary | Focus |
|---|---|---|
| E-commerce | Fraudster | Payment bypass, coupon abuse, fake returns |
| SaaS | Free-tier abuser | Rate-limit evasion, multi-accounting |
| Marketplace | Bad-faith seller | Fake listings, review manipulation, escrow games |
| API platform | Scraper | Rate-limit bypass, data harvesting |
| Social platform | Troll / bot farm | Spam, manipulation, fake engagement |

## Attack vector categories

| Category | Vectors | Example |
|---|---|---|
| Technical | Injection, auth bypass, race conditions, SSRF | SQLi in search parameter |
| Business logic | Workflow bypass, state manipulation, price tampering | Expired coupon replay via API |
| Social | Phishing, pretexting, authority exploitation | "I'm the CEO, I need access now" |
| Operational | Supply chain, dependency poisoning, insider | Compromised npm package in CI |
| Information | Data leakage, metadata, timing | User enumeration via login errors |
| Economic | Resource exhaustion, denial of wallet | Lambda invocation flood → $50K bill |

## Attack tree (for complex targets)

```
Goal: Steal user payment data
├── Path 1: Compromise the database
│   ├── SQLi in search endpoint
│   ├── Credential theft from env in logs
│   └── Exploit unpatched DB CVE
├── Path 2: Intercept in transit
│   ├── Downgrade TLS via misconfigured CDN
│   └── MITM on internal service mesh
└── Path 3: Abuse application logic
    ├── Export endpoint with insufficient ACL
    └── Admin panel with default credentials
```

## Perverse incentive detection

Systems create incentives. Sometimes those incentives reward the wrong
behavior.

| Question | What it reveals |
|---|---|
| "How will people game this?" | Loopholes in business logic |
| "What behavior does this reward that we don't want?" | Misaligned incentives |
| "Cheapest way to get the reward without the effort?" | Shortcut exploitation |
| "If we measure X, what Y gets sacrificed?" | Goodhart's Law |
| "Who benefits from this failing?" | Adversaries with motive |

### Common patterns

| Pattern | Example | Consequence |
|---|---|---|
| Metric gaming | "Lines of code" as productivity | Verbose, unmaintainable code |
| Reward hacking | Referral bonus with no verification | Fake accounts for self-referral |
| Race to the bottom | "Fastest response time" as SLA | Teams avoid complex tickets |
| Cobra effect | Bounty for reporting bugs | Team introduces bugs to claim bounties |
| Information asymmetry | Users know more than the system | Adverse selection in pricing |

## Competitive response

When the adversary is a competitor:

| Scenario | Framework |
|---|---|
| Feature parity | What can they copy? How fast? What's our defensible moat? |
| Price war | Can they sustain lower? What's their cost structure? |
| Talent poaching | Which roles are critical? How replaceable? Retention advantage? |
| Platform risk | Are we on their platform? Switch cost? |
| FUD campaign | What claims could they make? Which hardest to refute? |

## Output template

```markdown
## Red team: <target>

### Asset under assessment
<what's being protected and why it matters>

### Adversary profiles

#### Adversary 1: <name/role>
- Motivation: <why>
- Capability: <what they can do>
- Access: <what they start with>

#### Adversary 2: <name/role>
…

### Attack vectors (ranked)

| # | Vector | Adversary | Likelihood | Impact | Score |
|---|---|---|---|---|---|
| 1 | [Specific attack] | [Who] | H/M/L | H/M/L | [LxI] |
| 2 | … | … | … | … | … |

### Perverse incentives
| Incentive created | Unintended behavior | Severity |
|---|---|---|

### Recommended defenses
| Vector | Defense | Effort | Priority |
|---|---|---|---|
| #1 | [Specific countermeasure] | L/M/H | Immediate / Next sprint / Backlog |
```

## Anti-patterns

- **Generic adversaries.** "Attackers" — be specific. "External attacker
  motivated by payment-card theft."
- **Finding vectors that don't change behavior.** If the mitigation list
  doesn't change, the exercise didn't matter.
- **Paranoia cosplay.** Not every system faces nation-state threats.
  Calibrate adversary capability to reality.
- **Ignoring non-technical adversaries.** Regulators, opportunistic users,
  and perverse incentives do more damage to most products than APT campaigns.
