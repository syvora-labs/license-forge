<script setup lang="ts">
defineProps<{
    modelValue: boolean
    title?: string
}>()

const emit = defineEmits<{
    'update:modelValue': [value: boolean]
}>()

function close() {
    emit('update:modelValue', false)
}
</script>

<template>
    <Teleport to="body">
        <Transition name="drawer">
            <div v-if="modelValue" class="drawer-backdrop" @click.self="close">
                <div class="drawer-panel">
                    <div class="drawer-header">
                        <span v-if="title" class="drawer-title">{{ title }}</span>
                        <span v-else />
                        <button class="drawer-close" @click="close" aria-label="Close">
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                                stroke-width="2" stroke-linecap="round">
                                <line x1="18" y1="6" x2="6" y2="18" />
                                <line x1="6" y1="6" x2="18" y2="18" />
                            </svg>
                        </button>
                    </div>
                    <div class="drawer-body">
                        <slot />
                    </div>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>

<style scoped>
.drawer-backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.35);
    display: flex;
    align-items: flex-end;
    justify-content: center;
}

.drawer-panel {
    width: 100%;
    max-width: 500px;
    min-height: 60vh;
    max-height: 90vh;
    background: #fff;
    border-radius: 0.75rem 0.75rem 0 0;
    overflow-y: auto;
    box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.1);
}

.drawer-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.125rem 1.25rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.08);
    position: sticky;
    top: 0;
    background: #fff;
}

.drawer-title {
    font-size: 1.0625rem;
    font-weight: 700;
    color: var(--color-text);
}

.drawer-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2rem;
    height: 2rem;
    background: none;
    border: none;
    border-radius: 0.375rem;
    color: var(--color-text-muted);
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
}

.drawer-close:hover {
    background: rgba(0, 0, 0, 0.06);
    color: var(--color-text);
}

.drawer-body {
    padding: 0.75rem 0;
}

/* Transitions */
.drawer-enter-active,
.drawer-leave-active {
    transition: opacity 0.25s ease;
}

.drawer-enter-active .drawer-panel,
.drawer-leave-active .drawer-panel {
    transition: transform 0.25s cubic-bezier(0.32, 0.72, 0, 1);
}

.drawer-enter-from,
.drawer-leave-to {
    opacity: 0;
}

.drawer-enter-from .drawer-panel,
.drawer-leave-to .drawer-panel {
    transform: translateY(100%);
}
</style>
