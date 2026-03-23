<script setup lang="ts">
import { ref, computed } from 'vue'
import SyvoraDrawer from './SyvoraDrawer.vue'
import { useIsMobile } from '../composables/useIsMobile'

export interface TabItem {
    key: string
    label: string
    count?: number
}

const props = defineProps<{
    modelValue: string
    tabs: TabItem[]
}>()

const emit = defineEmits<{
    'update:modelValue': [key: string]
}>()

const drawerOpen = ref(false)
const isMobile = useIsMobile()

const activeTabItem = computed(() =>
    props.tabs.find(t => t.key === props.modelValue) ?? props.tabs[0]
)

function selectTab(key: string) {
    emit('update:modelValue', key)
    drawerOpen.value = false
}
</script>

<template>
    <!-- Desktop: horizontal tabs -->
    <div v-show="!isMobile" class="syvora-tabs syvora-tabs--desktop">
        <button
            v-for="tab in props.tabs"
            :key="tab.key"
            class="syvora-tab"
            :class="{ 'syvora-tab--active': props.modelValue === tab.key }"
            @click="emit('update:modelValue', tab.key)"
        >
            {{ tab.label }}
            <span v-if="tab.count !== undefined" class="syvora-tab-count">{{ tab.count }}</span>
        </button>
    </div>

    <!-- Mobile: trigger + drawer -->
    <div v-show="isMobile" class="syvora-tabs-mobile">
        <button class="syvora-tabs-trigger" @click="drawerOpen = true">
            <span class="trigger-label">{{ activeTabItem?.label }}</span>
            <span v-if="activeTabItem?.count !== undefined" class="syvora-tab-count">{{ activeTabItem.count }}</span>
            <svg class="trigger-chevron" width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M4 6l4 4 4-4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
        </button>

        <SyvoraDrawer v-model="drawerOpen" title="Select tab">
            <button
                v-for="tab in props.tabs"
                :key="tab.key"
                class="drawer-tab-row"
                :class="{ 'drawer-tab-row--active': props.modelValue === tab.key }"
                @click="selectTab(tab.key)"
            >
                <span class="drawer-tab-label">{{ tab.label }}</span>
                <span v-if="tab.count !== undefined" class="syvora-tab-count">{{ tab.count }}</span>
            </button>
        </SyvoraDrawer>
    </div>
</template>

<style scoped>
/* ── Desktop tabs ── */
.syvora-tabs--desktop {
    display: flex;
    gap: 0.25rem;
    border-bottom: 1px solid var(--color-border-subtle, rgba(0, 0, 0, 0.07));
    margin-bottom: 1.5rem;
}

.syvora-tab {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    font-size: 0.9375rem;
    font-weight: 500;
    color: var(--color-text-muted);
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    margin-bottom: -1px;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
    font-family: inherit;
}

.syvora-tab:hover {
    color: var(--color-text);
}

.syvora-tab--active {
    color: var(--color-text);
    border-bottom-color: var(--color-accent);
}

.syvora-tab-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 1.25rem;
    padding: 0.1rem 0.45rem;
    border-radius: 999px;
    font-size: 0.75rem;
    font-weight: 600;
    background: rgba(115, 195, 254, 0.12);
    color: var(--color-accent);
}

/* ── Mobile trigger + drawer ── */
.syvora-tabs-mobile {
    margin-bottom: 1.5rem;
}

.syvora-tabs-trigger {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.625rem 1rem;
    background: var(--color-surface, #fff);
    border: 1px solid var(--color-border, rgba(0, 0, 0, 0.07));
    border-radius: 0.75rem;
    font-size: 0.9375rem;
    font-weight: 600;
    color: var(--color-text);
    cursor: pointer;
    font-family: inherit;
    transition: border-color 0.15s;
}

.syvora-tabs-trigger:hover {
    border-color: var(--color-accent);
}

.trigger-label {
    flex: 1;
    text-align: left;
}

.trigger-chevron {
    flex-shrink: 0;
    color: var(--color-text-muted);
}

/* Drawer tab rows */
.drawer-tab-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    padding: 0.875rem 1.25rem;
    background: none;
    border: none;
    border-left: 3px solid transparent;
    font-size: 0.9375rem;
    font-weight: 500;
    color: var(--color-text-muted);
    cursor: pointer;
    font-family: inherit;
    transition: background 0.1s, color 0.1s;
}

.drawer-tab-row:hover {
    background: rgba(0, 0, 0, 0.03);
    color: var(--color-text);
}

.drawer-tab-row--active {
    color: var(--color-text);
    border-left-color: var(--color-accent);
    background: rgba(115, 195, 254, 0.06);
    font-weight: 600;
}

.drawer-tab-label {
    flex: 1;
    text-align: left;
}

/* ── Responsive ── */
</style>
