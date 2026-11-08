# Knowledge

Shared, public. Nothing here may identify a person or a home: no IPs, MACs, hostnames, usernames, serials or tokens.

## Sources

`sources/<platform>.md`: where to look before acting on that platform (news that needs manual intervention, security notes, update channels, platform traps).

## References

`references.md`: open-source data and checklists to read at visit time before writing a host script (app leftovers, game saves, usage history, package-manager steps, perf triage).

## Kinds

`kinds.json`: the kinds of fact a case item can have (`kind` in `cases.jsonl`), each with a description and the free labels it groups. A label belongs to one kind only. A guess at a cause is a `hypothesis`, not a `root cause`; a fix tried or suggested is a `proposed fix` until it's confirmed to work, then a `resolution` (`cw search` reads any resolution as fixed).
