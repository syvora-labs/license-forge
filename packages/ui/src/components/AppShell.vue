<script setup lang="ts">
import { ref } from 'vue'
import { useIsMobile } from '../composables/useIsMobile'

const drawerOpen = ref(false)
const isMobile = useIsMobile()
</script>

<template>
    <div class="shell">
        <header class="shell-header">
            <div class="shell-header-inner">
                <div class="shell-left">
                    <button v-show="isMobile" class="shell-hamburger" @click="drawerOpen = true" aria-label="Open menu">
                        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                            stroke-width="2" stroke-linecap="round">
                            <line x1="3" y1="6" x2="21" y2="6" />
                            <line x1="3" y1="12" x2="21" y2="12" />
                            <line x1="3" y1="18" x2="21" y2="18" />
                        </svg>
                    </button>
                    <div class="shell-logo">
                        <slot name="logo" />
                    </div>
                </div>

                <div v-show="!isMobile" class="shell-nav">
                    <slot name="nav" />
                </div>

                <div v-if="isMobile" class="shell-actions-mobile">
                    <slot name="actions-mobile" />
                </div>

                <div v-show="!isMobile" class="shell-actions">
                    <slot name="actions" />
                </div>
            </div>
        </header>

        <!-- Mobile drawer -->
        <Teleport to="body">
            <Transition name="shell-drawer">
                <div v-if="drawerOpen" class="shell-drawer-backdrop" @click.self="drawerOpen = false">
                    <div class="shell-drawer-panel">
                        <div class="shell-drawer-header">
                            <div class="shell-logo">
                                <slot name="logo" />
                            </div>
                            <button class="shell-drawer-close" @click="drawerOpen = false"
                                aria-label="Close menu">&times;</button>
                        </div>
                        <nav class="shell-drawer-nav" @click="drawerOpen = false">
                            <slot name="nav" />
                        </nav>
                        <div class="shell-drawer-actions" @click="drawerOpen = false">
                            <slot name="actions" />
                        </div>
                    </div>
                </div>
            </Transition>
        </Teleport>

        <div v-if="$slots.notice" class="shell-notice">
            <slot name="notice" />
        </div>

        <main class="shell-main">
            <slot />
        </main>

        <footer class="shell-footer">
            <slot name="footer" />
        </footer>
    </div>
</template>

<style scoped>
.shell {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

.shell-header {
    position: sticky;
    top: 0;
    z-index: 100;
    padding: 0 1.5rem;
    height: 4rem;
    display: flex;
    align-items: center;
    background: #fff;
    border-bottom: 1px solid rgba(0, 0, 0, 0.08);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
}

.shell-header-inner {
    max-width: 960px;
    width: 100%;
    margin: 0 auto;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
}

.shell-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-shrink: 0;
}

.shell-hamburger {
    display: flex;
    align-items: center;
    justify-content: center;
    background: none;
    border: none;
    cursor: pointer;
    padding: 0.25rem;
    border-radius: 0.375rem;
    color: var(--color-text);
    transition: background 0.15s;
}

.shell-hamburger:hover {
    background: rgba(0, 0, 0, 0.06);
}

.shell-logo {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 700;
    font-size: 1.125rem;
    flex-shrink: 0;
}

:slotted(.logo-icon) {
    font-size: 1.4rem;
}

:slotted(.logo-text) {
    color: inherit;
    text-decoration: none;
}

.shell-nav {
    display: flex;
    gap: 1.25rem;
    flex: 1;
    padding-left: 1.5rem;
}

.shell-nav :deep(.nav-link) {
    font-size: 0.875rem;
    font-weight: 500;
    color: rgba(10, 26, 18, 0.5);
    text-decoration: none;
    padding: 0.25rem 0.625rem;
    border-radius: 0.5rem;
    transition: color 0.15s, background 0.15s;
}

.shell-nav :deep(.nav-link:hover) {
    color: var(--color-text);
    background: rgba(0, 0, 0, 0.04);
}

.shell-nav :deep(.nav-link--active) {
    color: var(--color-accent);
    background: rgba(115, 195, 254, 0.12);
    font-weight: 600;
}

.shell-actions {
    flex-shrink: 0;
}

.shell-actions-mobile {
    margin-left: auto;
    flex-shrink: 0;
}

.shell-notice {
    /* full-width notice bar — SyvoraAlert handles its own background */
}

.shell-main {
    flex: 1;
    padding: 3rem 1.5rem 2rem;
}

.shell-footer {
    border-top: 1px solid rgba(0, 0, 0, 0.06);
    padding: 1rem 1.5rem;
    text-align: center;
    font-size: 0.8rem;
    color: var(--color-text-muted);
    background: #fff;
}

:slotted(.footer a) {
    color: var(--color-accent);
    text-decoration: none;
}

/* ── Drawer (mobile) ── */

.shell-drawer-backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.4);
}

.shell-drawer-panel {
    position: absolute;
    top: 0;
    left: 0;
    bottom: 0;
    width: 280px;
    max-width: 80vw;
    background: #fff;
    box-shadow: 4px 0 24px rgba(0, 0, 0, 0.12);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
}

.shell-drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem;
    border-bottom: 1px solid rgba(0, 0, 0, 0.08);
}

.shell-drawer-close {
    background: none;
    border: none;
    font-size: 1.5rem;
    line-height: 1;
    color: var(--color-text-muted);
    cursor: pointer;
    padding: 0.25rem;
}

.shell-drawer-nav {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.75rem;
    flex: 1;
}

.shell-drawer-nav :deep(.nav-link) {
    font-size: 0.9375rem;
    font-weight: 500;
    color: rgba(10, 26, 18, 0.6);
    text-decoration: none;
    padding: 0.625rem 0.75rem;
    border-radius: 0.5rem;
    transition: color 0.15s, background 0.15s;
}

.shell-drawer-nav :deep(.nav-link:hover) {
    color: var(--color-text);
    background: rgba(0, 0, 0, 0.04);
}

.shell-drawer-nav :deep(.nav-link--active) {
    color: var(--color-accent);
    background: rgba(115, 195, 254, 0.12);
    font-weight: 600;
}

.shell-drawer-actions {
    padding: 0.75rem 1.25rem;
    border-top: 1px solid rgba(0, 0, 0, 0.08);
}

/* Drawer transitions */
.shell-drawer-enter-active,
.shell-drawer-leave-active {
    transition: opacity 0.2s ease;
}

.shell-drawer-enter-active .shell-drawer-panel,
.shell-drawer-leave-active .shell-drawer-panel {
    transition: transform 0.2s ease;
}

.shell-drawer-enter-from,
.shell-drawer-leave-to {
    opacity: 0;
}

.shell-drawer-enter-from .shell-drawer-panel,
.shell-drawer-leave-to .shell-drawer-panel {
    transform: translateX(-100%);
}

/* ── Mobile ── */

@media (max-width: 600px) {
    .shell-header {
        padding: 0 1rem;
    }

    .shell-main {
        padding: 1.5rem 1rem 1.5rem;
    }
}
</style>
