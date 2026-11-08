#!/bin/sh
# Probe: containers. State, restarts, health, OOM kills, limits, resource use, bind mounts, images, disk use. Read-only.
# No logs, no env, no full inspect: those hold secrets. Run for "a service is down or slow" or space taken by Docker.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

has docker || { echo "no docker"; exit 0; }

sec version
docker version --format 'client {{.Client.Version}}'
docker compose version --short | sed 's/^/compose /'
docker info --format 'server {{.ServerVersion}}' | grep -v 'server $' ||
  { echo "daemon not reachable: not running, or this user can't use the socket"; echo '```'; exit 0; }

sec containers
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' | sort

# memlimit 0 = no limit. oom=true: the kernel killed it for memory, a restart loop often follows.
sec restarts-health-oom
ids=$(docker ps -aq)
[ -n "$ids" ] && docker inspect --format '{{.Name}} restarts={{.RestartCount}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}} policy={{.HostConfig.RestartPolicy.Name}} memlimit={{.HostConfig.Memory}}' $ids | sed 's#^/##' | sort

sec stats
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' | sort -t "$(printf '\t')" -k4 -rn

# Which container uses which host path: check this before deleting anything a container might bind.
sec bind-mounts
[ -n "$ids" ] && docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{$.Name}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}{{end}}' $ids |
  sed 's#^/##' | grep -v -E ' /(etc|var/run|run|proc|sys|dev)(/| |$)' | grep . | sort

sec images-by-size
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.CreatedSince}}' | sort -rh | head -12

sec system-df
docker system df

echo '```'
exit 0
