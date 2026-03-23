<script setup lang="ts">
import { ref, computed, watch, nextTick } from 'vue'

export interface CommandItem {
    id: string
    label: string
    group?: string
    keywords?: string[]
}

const props = defineProps<{
    modelValue: boolean
    items: CommandItem[]
}>()

const emit = defineEmits<{
    'update:modelValue': [value: boolean]
    select: [item: CommandItem]
}>()

const query = ref('')
const selectedIndex = ref(0)
const inputRef = ref<HTMLInputElement | null>(null)

const filtered = computed(() => {
    const q = query.value.toLowerCase().trim()
    if (!q) return props.items
    return props.items.filter((item) => {
        if (item.label.toLowerCase().includes(q)) return true
        return item.keywords?.some((kw) => kw.toLowerCase().includes(q)) ?? false
    })
})

const groupedFiltered = computed(() => {
    const map = new Map<string, CommandItem[]>()
    for (const item of filtered.value) {
        const group = item.group ?? ''
        if (!map.has(group)) map.set(group, [])
        map.get(group)!.push(item)
    }
    return map
})

watch(
    () => props.modelValue,
    (open) => {
        if (open) {
            query.value = ''
            selectedIndex.value = 0
            nextTick(() => inputRef.value?.focus())
        }
    },
)

watch(query, () => {
    selectedIndex.value = 0
})

function close() {
    emit('update:modelValue', false)
}

function selectCurrent() {
    const item = filtered.value[selectedIndex.value]
    if (item) {
        emit('select', item)
        close()
    }
}

function onKeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowDown') {
        e.preventDefault()
        selectedIndex.value = Math.min(selectedIndex.value + 1, filtered.value.length - 1)
    } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        selectedIndex.value = Math.max(selectedIndex.value - 1, 0)
    } else if (e.key === 'Enter') {
        e.preventDefault()
        selectCurrent()
    } else if (e.key === 'Escape') {
        close()
    }
}

function getFlatIndex(item: CommandItem): number {
    return filtered.value.indexOf(item)
}
</script>

<template>
    <Teleport to="body">
        <Transition name="palette">
            <div v-if="modelValue" class="palette-overlay" @click.self="close">
                <div class="palette-panel" @keydown="onKeydown">
                    <div class="palette-search">
                        <svg class="palette-search-icon" width="18" height="18" viewBox="0 0 24 24" fill="none"
                            stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                            <circle cx="11" cy="11" r="8" />
                            <line x1="21" y1="21" x2="16.65" y2="16.65" />
                        </svg>
                        <input ref="inputRef" v-model="query" class="palette-input" placeholder="Search pages..."
                            type="text" />
                        <kbd class="palette-kbd">esc</kbd>
                    </div>

                    <div class="palette-results">
                        <template v-if="filtered.length === 0">
                            <div class="palette-empty">No results found</div>
                        </template>
                        <template v-else>
                            <div v-for="[group, items] in groupedFiltered" :key="group" class="palette-group">
                                <div v-if="group" class="palette-group-label">{{ group }}</div>
                                <button v-for="item in items" :key="item.id" class="palette-item"
                                    :class="{ 'palette-item--active': getFlatIndex(item) === selectedIndex }"
                                    @click="emit('select', item); close()"
                                    @mouseenter="selectedIndex = getFlatIndex(item)">
                                    <span class="palette-item-label">{{ item.label }}</span>
                                </button>
                            </div>
                        </template>
                    </div>

                    <div class="palette-footer">
                        <span class="palette-hint"><kbd>&uarr;</kbd><kbd>&darr;</kbd> navigate</span>
                        <span class="palette-hint"><kbd>&crarr;</kbd> select</span>
                        <span class="palette-hint"><kbd>esc</kbd> close</span>
                    </div>
                </div>
            </div>
        </Transition>
    </Teleport>
</template>

<style scoped>
.palette-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 18vh;
    z-index: 2000;
}

.palette-panel {
    background: #fff;
    border: 1px solid rgba(0, 0, 0, 0.08);
    border-radius: 1.25rem;
    width: 100%;
    max-width: 520px;
    margin: 0 1rem;
    display: flex;
    flex-direction: column;
    max-height: 420px;
    overflow: hidden;
    box-shadow:
        0 8px 32px rgba(0, 0, 0, 0.12),
        0 32px 64px rgba(0, 0, 0, 0.08);
}

.palette-search {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    padding: 0.875rem 1rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.06);
}

.palette-search-icon {
    flex-shrink: 0;
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
}

.palette-input {
    flex: 1;
    border: none;
    background: none;
    font-size: 0.9375rem;
    color: var(--color-text, #0c1a27);
    outline: none;
    font-family: inherit;
}

.palette-input::placeholder {
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
}

.palette-kbd {
    font-size: 0.625rem;
    font-family: inherit;
    padding: 0.125rem 0.375rem;
    border-radius: 0.25rem;
    background: rgba(0, 0, 0, 0.06);
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
}

.palette-results {
    overflow-y: auto;
    flex: 1;
    padding: 0.5rem;
}

.palette-group {
    margin-bottom: 0.25rem;
}

.palette-group-label {
    font-size: 0.68rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
    padding: 0.5rem 0.625rem 0.25rem;
}

.palette-item {
    display: flex;
    align-items: center;
    width: 100%;
    padding: 0.5rem 0.625rem;
    border: none;
    background: none;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: background 0.1s;
    text-align: left;
    font-family: inherit;
}

.palette-item:hover,
.palette-item--active {
    background: rgba(115, 195, 254, 0.12);
}

.palette-item-label {
    font-size: 0.875rem;
    font-weight: 500;
    color: var(--color-text, #0c1a27);
}

.palette-empty {
    padding: 2rem 1rem;
    text-align: center;
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
    font-size: 0.8125rem;
}

.palette-footer {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.5rem 1rem;
    border-top: 1px solid rgba(0, 0, 0, 0.06);
    background: #fafafa;
}

.palette-hint {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.6875rem;
    color: var(--color-text-muted, rgba(12, 26, 39, 0.48));
}

.palette-hint kbd {
    font-size: 0.625rem;
    font-family: inherit;
    padding: 0.0625rem 0.3rem;
    border-radius: 0.25rem;
    background: rgba(0, 0, 0, 0.06);
    font-weight: 600;
    min-width: 1.125rem;
    text-align: center;
}

/* Transitions */
.palette-enter-active,
.palette-leave-active {
    transition: opacity 0.15s ease;
}

.palette-enter-active .palette-panel,
.palette-leave-active .palette-panel {
    transition: transform 0.15s ease, opacity 0.15s ease;
}

.palette-enter-from,
.palette-leave-to {
    opacity: 0;
}

.palette-enter-from .palette-panel,
.palette-leave-to .palette-panel {
    transform: scale(0.96) translateY(-8px);
    opacity: 0;
}

@media (max-width: 600px) {
    .palette-overlay {
        padding-top: 10vh;
    }

    .palette-footer {
        display: none;
    }
}
</style>
