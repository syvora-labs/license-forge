<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import { RouterView, RouterLink, useRoute, useRouter } from 'vue-router'
import {
    AppShell,
    SyvoraAvatar,
    SyvoraCommandPalette,
    type CommandItem,
} from '@syvora/ui'
import { useHotkey } from '@syvora/ui'
import { useAuth } from './composables/useAuth'
import { useProfile } from './composables/useProfile'
import { useMandator } from './composables/useMandator'

const route = useRoute()
const router = useRouter()

const { user, session, loading: authLoading, signOut } = useAuth()
const { profile, fetchProfile } = useProfile()
const {
    mandator,
    mandators,
    currentRole,
    MODULE_DEFINITIONS,
    isModuleEnabled,
    fetchMandators,
    selectMandator,
} = useMandator()

const isAuthenticated = computed(() => !!session.value)
const isAuthRoute = computed(() => route.meta.requiresAuth === false)

// User menu dropdown
const showUserMenu = ref(false)

// Mandator command palette
const showPalette = ref(false)
useHotkey('k', () => {
    if (isAuthenticated.value && mandators.value.length > 1) {
        showPalette.value = !showPalette.value
    }
})

const mandatorItems = computed<CommandItem[]>(() =>
    mandators.value.map((m) => ({
        id: m.id,
        label: m.name,
        group: 'Organisations',
        keywords: [m.slug],
    })),
)

function onSelectMandator(item: CommandItem) {
    selectMandator(item.id)
}

// Nav items
const navItems = computed(() => {
    const items: { to: string; label: string }[] = [
        { to: '/', label: 'Home' },
    ]

    for (const mod of MODULE_DEFINITIONS) {
        if (isModuleEnabled(mod.route)) {
            items.push({ to: `/${mod.route}`, label: mod.label })
        }
    }

    if (currentRole.value === 'admin') {
        items.push({ to: '/admin', label: 'Admin' })
    }

    return items
})

function navLinkClass(to: string) {
    const active = route.path === to || (to !== '/' && route.path.startsWith(to))
    return ['nav-link', active ? 'nav-link--active' : '']
}

async function handleSignOut() {
    showUserMenu.value = false
    await signOut()
    router.push('/login')
}

function handleUserMenuClick() {
    showUserMenu.value = !showUserMenu.value
}

function goToProfile() {
    showUserMenu.value = false
    router.push('/profile')
}

// Load user data on auth
watch(
    () => session.value,
    async (s) => {
        if (s) {
            await Promise.all([fetchProfile(), fetchMandators()])
        }
    },
)

onMounted(async () => {
    if (session.value) {
        await Promise.all([fetchProfile(), fetchMandators()])
    }
})

const displayName = computed(() =>
    profile.value?.display_name || user.value?.email || '',
)

const modKey = typeof globalThis.navigator !== 'undefined' && globalThis.navigator.platform.includes('Mac') ? '⌘' : 'Ctrl'
</script>

<template>
    <!-- Auth pages: no shell -->
    <RouterView v-if="isAuthRoute" />

    <!-- Authenticated: full shell -->
    <AppShell v-else-if="!authLoading">
        <template #logo>
            <RouterLink to="/" class="logo-text">License Forge</RouterLink>
        </template>

        <template #nav>
            <RouterLink
                v-for="item in navItems"
                :key="item.to"
                :to="item.to"
                :class="navLinkClass(item.to)"
            >
                {{ item.label }}
            </RouterLink>
        </template>

        <template #actions>
            <div class="shell-action-group">
                <button
                    v-if="mandators.length > 1"
                    class="mandator-btn"
                    @click="showPalette = true"
                    :title="`Switch organisation (${modKey}+K)`"
                >
                    {{ mandator?.name ?? 'Select org' }}
                </button>

                <div class="user-menu-wrap">
                    <SyvoraAvatar
                        :name="displayName"
                        :src="profile?.avatar_url"
                        size="sm"
                        editable
                        @click="handleUserMenuClick"
                    />
                    <div v-if="showUserMenu" class="user-menu" @click="showUserMenu = false">
                        <button class="user-menu-item" @click="goToProfile">Profile</button>
                        <button class="user-menu-item" @click="handleSignOut">Sign out</button>
                    </div>
                </div>
            </div>
        </template>

        <template #actions-mobile>
            <SyvoraAvatar
                :name="displayName"
                :src="profile?.avatar_url"
                size="sm"
                editable
                @click="handleUserMenuClick"
            />
            <div v-if="showUserMenu" class="user-menu user-menu--mobile" @click="showUserMenu = false">
                <button class="user-menu-item" @click="goToProfile">Profile</button>
                <button class="user-menu-item" @click="handleSignOut">Sign out</button>
            </div>
        </template>

        <RouterView />
    </AppShell>

    <!-- Mandator palette -->
    <SyvoraCommandPalette
        v-model="showPalette"
        :items="mandatorItems"
        @select="onSelectMandator"
    />
</template>

<style scoped>
.logo-text {
    color: inherit;
    text-decoration: none;
    font-weight: 700;
    font-size: 1.125rem;
}

.shell-action-group {
    display: flex;
    align-items: center;
    gap: 0.75rem;
}

.mandator-btn {
    background: rgba(0, 0, 0, 0.04);
    border: 1px solid rgba(0, 0, 0, 0.08);
    border-radius: 0.5rem;
    padding: 0.375rem 0.75rem;
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--color-text);
    cursor: pointer;
    transition: background 0.15s;
    font-family: inherit;
}

.mandator-btn:hover {
    background: rgba(0, 0, 0, 0.08);
}

.user-menu-wrap {
    position: relative;
}

.user-menu {
    position: absolute;
    right: 0;
    top: calc(100% + 0.5rem);
    background: #fff;
    border: 1px solid rgba(0, 0, 0, 0.08);
    border-radius: 0.75rem;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.1);
    overflow: hidden;
    min-width: 140px;
    z-index: 200;
}

.user-menu--mobile {
    position: fixed;
    right: 1rem;
    top: 3.5rem;
}

.user-menu-item {
    display: block;
    width: 100%;
    padding: 0.625rem 1rem;
    border: none;
    background: none;
    text-align: left;
    font-size: 0.875rem;
    color: var(--color-text);
    cursor: pointer;
    font-family: inherit;
    transition: background 0.1s;
}

.user-menu-item:hover {
    background: rgba(0, 0, 0, 0.04);
}
</style>
