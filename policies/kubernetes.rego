package main

import rego.v1

charges_de_travail := {"Deployment", "Rollout", "StatefulSet", "DaemonSet"}

registre_autorise := "ghcr.io/9m7fjfpv9k-cyber/"

# Récupérer les conteneurs des ressources qui créent des pods.
conteneurs contains c if {
    charges_de_travail[input.kind]
    some c in input.spec.template.spec.containers
}

# PSSI-R1 : chaque image doit avoir un tag explicite.
deny contains msg if {
    some c in conteneurs
    not contains(c.image, ":")
    msg := sprintf("PSSI-R1 : l'image du conteneur '%s' n'a pas de tag explicite (%s)", [c.name, c.image])
}

# PSSI-R1 : le tag latest est interdit.
deny contains msg if {
    some c in conteneurs
    endswith(c.image, ":latest")
    msg := sprintf("PSSI-R1 : le conteneur '%s' utilise le tag latest (%s)", [c.name, c.image])
}

# PSSI-R2 : les images doivent venir du registre autorisé.
deny contains msg if {
    some c in conteneurs
    not startswith(c.image, registre_autorise)
    msg := sprintf("PSSI-R2 : l'image du conteneur '%s' ne vient pas du registre autorisé (%s)", [c.name, c.image])
}

# PSSI-R3 : chaque conteneur doit avoir une limite de mémoire.
deny contains msg if {
    some c in conteneurs
    not c.resources.limits.memory
    msg := sprintf("PSSI-R3 : le conteneur '%s' doit avoir une limite de mémoire", [c.name])
}

# PSSI-R4 : vérifier la déclaration non-root au niveau du pod.
pod_non_root if {
    input.spec.template.spec.securityContext.runAsNonRoot == true
}

deny contains msg if {
    charges_de_travail[input.kind]
    not pod_non_root
    msg := sprintf("PSSI-R4 : le pod de '%s' doit déclarer securityContext.runAsNonRoot: true", [input.metadata.name])
}