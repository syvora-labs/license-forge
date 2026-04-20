<script setup lang="ts">
import { computed } from 'vue'
import { SyvoraCard, SyvoraEmptyState } from '@syvora/ui'
import { useAuth } from '../composables/useAuth'
import { useProfile } from '../composables/useProfile'
import { useMandator } from '../composables/useMandator'

const { user } = useAuth()
const { profile } = useProfile()
const { MODULE_DEFINITIONS, isModuleEnabled, mandator } = useMandator()

const greeting = computed(() => {
    const name = profile.value?.display_name || user.value?.email || 'there'
    return `Welcome, ${name}`
})

const visibleModules = computed(() =>
    MODULE_DEFINITIONS.filter((m) => isModuleEnabled(m.route)),
)
</script>

<template>
    <div class="home">
        <h1 class="home-greeting">{{ greeting }}</h1>

        <p v-if="mandator" class="home-org">{{ mandator.name }}</p>

        <div v-if="visibleModules.length" class="home-grid">
            <RouterLink
                v-for="mod in visibleModules"
                :key="mod.route"
                :to="`/${mod.route}`"
                class="home-tile"
            >
                <SyvoraCard :title="mod.label">
                    <p class="home-tile-desc">Open {{ mod.label }}</p>
                </SyvoraCard>
            </RouterLink>
        </div>

        <SyvoraEmptyState v-else>
            No modules are enabled for this organisation. Contact your administrator.
        </SyvoraEmptyState>
    </div>
</template>

<style scoped>
.home {
    max-width: 960px;
    margin: 0 auto;
}

.home-greeting {
    font-size: 1.5rem;
    font-weight: 700;
    margin: 0 0 0.25rem;
}

.home-org {
    font-size: 0.875rem;
    color: var(--color-text-muted);
    margin: 0 0 2rem;
}

.home-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    gap: 1rem;
}

.home-tile {
    text-decoration: none;
    color: inherit;
}

.home-tile-desc {
    font-size: 0.8125rem;
    color: var(--color-text-muted);
    margin: 0;
}
</style>
