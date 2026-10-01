/* The v0.49.1 excerpt with the minimal NULL guards (the fix drafted for upstream). */
static double
dpi_for_os_window(const OSWindow *os_window) {
    double dpi = 0;
    if (os_window->fonts_data) dpi = (os_window->fonts_data->logical_dpi_x + os_window->fonts_data->logical_dpi_y) / 2.;
    if (dpi == 0) dpi = (global_state.default_dpi.x + global_state.default_dpi.y) / 2.;
    return dpi;
}

PYWRAP1(viewport_for_window) {
    id_type os_window_id;
    int vw = 100, vh = 100;
    unsigned int cell_width = 1, cell_height = 1;
    PA("K", &os_window_id);
    Region central = {0}, tab_bar = {0};
    WITH_OS_WINDOW(os_window_id)
    os_window_regions(os_window, &central, &tab_bar);
    vw = os_window->viewport_width;
    vh = os_window->viewport_height;
    if (!os_window->fonts_data) goto end;
    cell_width = os_window->fonts_data->fcm.cell_width;
    cell_height = os_window->fonts_data->fcm.cell_height;
    goto end;
    END_WITH_OS_WINDOW
end:
    return Py_BuildValue("NNiiII", wrap_region(&central), wrap_region(&tab_bar), vw, vh, cell_width, cell_height);
}

PYWRAP1(cell_size_for_window) {
    id_type os_window_id;
    unsigned int cell_width = 0, cell_height = 0;
    PA("K", &os_window_id);
    WITH_OS_WINDOW(os_window_id)
    if (!os_window->fonts_data) goto end;
    cell_width = os_window->fonts_data->fcm.cell_width;
    cell_height = os_window->fonts_data->fcm.cell_height;
    goto end;
    END_WITH_OS_WINDOW
end:
    return Py_BuildValue("II", cell_width, cell_height);
}
