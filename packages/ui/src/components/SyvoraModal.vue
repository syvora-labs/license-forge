<script setup lang="ts">
defineProps<{
    title: string
    size?: 'sm' | 'md' | 'lg'
}>()

const emit = defineEmits<{ close: [] }>()
</script>

<template>
    <div class="syvora-modal-overlay" @click.self="emit('close')">
        <div
            class="syvora-modal"
            :class="`syvora-modal--${size ?? 'md'}`"
            role="dialog"
            aria-modal="true"
        >
            <div class="syvora-modal-header">
                <h2 class="syvora-modal-title">{{ title }}</h2>
                <button class="syvora-modal-close" aria-label="Close" @click="emit('close')">✕</button>
            </div>

            <div class="syvora-modal-body">
                <slot />
            </div>

            <div v-if="$slots.footer" class="syvora-modal-footer">
                <slot name="footer" />
            </div>
        </div>
    </div>
</template>

<style scoped>
.syvora-modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: 1rem;
}

.syvora-modal {
    background: #fff;
    border: 1px solid rgba(0, 0, 0, 0.08);
    border-radius: 1.5rem;
    width: 100%;
    display: flex;
    flex-direction: column;
    max-height: 90vh;
    overflow: hidden;
    box-shadow:
        0 8px 32px rgba(0, 0, 0, 0.12),
        0 32px 64px rgba(0, 0, 0, 0.08);
}

.syvora-modal--sm { max-width: 360px; }
.syvora-modal--md { max-width: 480px; }
.syvora-modal--lg { max-width: 640px; }

.syvora-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1.125rem 1.375rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.06);
    flex-shrink: 0;
    background: #fafafa;
}

.syvora-modal-title {
    font-size: 1.0625rem;
    font-weight: 700;
    margin: 0;
    color: var(--color-text);
    letter-spacing: -0.01em;
}

.syvora-modal-close {
    background: rgba(0, 0, 0, 0.06);
    border: none;
    color: var(--color-text-muted);
    cursor: pointer;
    font-size: 0.8rem;
    padding: 0;
    width: 1.75rem;
    height: 1.75rem;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s, color 0.15s;
    line-height: 1;
}

.syvora-modal-close:hover {
    background: rgba(0, 0, 0, 0.1);
    color: var(--color-text);
}

.syvora-modal-body {
    padding: 1.375rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
    overflow-y: auto;
}

.syvora-modal-footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 0.625rem;
    padding: 1rem 1.375rem;
    border-top: 1px solid rgba(0, 0, 0, 0.06);
    flex-shrink: 0;
    background: #fafafa;
}
</style>
