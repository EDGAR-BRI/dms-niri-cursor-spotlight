#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

static const struct wl_interface *vptr_types[] = {
    NULL, NULL, NULL, NULL, NULL
};

extern const struct wl_interface zwlr_virtual_pointer_v1_interface;

static const struct wl_message vptr_mgr_requests[] = {
    { "create_virtual_pointer", "?on", vptr_types + 0 },
    { "destroy", "", vptr_types + 0 },
    { "create_virtual_pointer_with_output", "2?o?on", vptr_types + 0 },
};

const struct wl_interface zwlr_virtual_pointer_manager_v1_interface = {
    "zwlr_virtual_pointer_manager_v1", 2,
    3, vptr_mgr_requests,
    0, NULL,
};

static const struct wl_message vptr_requests[] = {
    { "motion", "uff", vptr_types + 0 },
    { "motion_absolute", "uuuuu", vptr_types + 0 },
    { "button", "uuu", vptr_types + 0 },
    { "axis", "uuf", vptr_types + 0 },
    { "frame", "", vptr_types + 0 },
    { "axis_source", "u", vptr_types + 0 },
    { "axis_stop", "uu", vptr_types + 0 },
    { "axis_discrete", "uuf", vptr_types + 0 },
    { "destroy", "", vptr_types + 0 },
};

const struct wl_interface zwlr_virtual_pointer_v1_interface = {
    "zwlr_virtual_pointer_v1", 2,
    9, vptr_requests,
    0, NULL,
};

struct wl_proxy *vptr_mgr = NULL;

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, "zwlr_virtual_pointer_manager_v1") == 0) {
        vptr_mgr = wl_registry_bind(registry, name,
                                    &zwlr_virtual_pointer_manager_v1_interface, 1);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

int main(void) {
    vptr_types[0] = &wl_seat_interface;
    vptr_types[1] = &zwlr_virtual_pointer_v1_interface;

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);

    if (vptr_mgr) {
        struct wl_proxy *vptr = wl_proxy_marshal_flags(
            vptr_mgr, 0, &zwlr_virtual_pointer_v1_interface,
            wl_proxy_get_version(vptr_mgr), 0, NULL, NULL);
        if (vptr) {
            /* Move +1px then -1px (wl_fixed_from_int(1) = 256) so net delta is 0 */
            wl_proxy_marshal(vptr, 0, 0u, wl_fixed_from_int(1), wl_fixed_from_int(0));
            wl_proxy_marshal(vptr, 4); /* frame */
            wl_proxy_marshal(vptr, 0, 1u, wl_fixed_from_int(-1), wl_fixed_from_int(0));
            wl_proxy_marshal(vptr, 4); /* frame */
            wl_display_roundtrip(display);
            wl_proxy_marshal_flags(vptr, 8, NULL, wl_proxy_get_version(vptr), WL_MARSHAL_FLAG_DESTROY);
        }
        wl_proxy_marshal_flags(vptr_mgr, 1, NULL, wl_proxy_get_version(vptr_mgr), WL_MARSHAL_FLAG_DESTROY);
    }

    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return 0;
}
