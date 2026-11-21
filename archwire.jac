graph layers {
    layer shared { model; util; }
    layer service { manager; }
    layer ui { ui.*; }
    layer pages { web | pages.*; }
}

graph spaces {
    space api: native { manager; }
    space site: browser { entry web; pages.* | ui.*; }

    app manager { run api; serve site; }
}

graph import {
    edge Shared: shared --> service | ui | pages;
    edge Calls: service --> pages;
    edge Ui: ui --> pages;

    model ++> manager { TagOut, ProfileOut, ArtifactOut, OkReply, ProfileReply, ProfilesReply, ArtifactReply, ArtifactsReply, FileReply, LaunchReply, StatusOut, SettingsOut, ConfigOut, AuthStatusOut }
    util ++> manager { safe_filename, mask_key, sidebar_width, data_dir }
    model ++> pages.index { ProfileOut, ArtifactOut, OkReply, ProfileReply, ProfilesReply, ArtifactsReply, LaunchReply, StatusOut, SettingsOut }
    model ++> ui.profile_list { ProfileOut }
    model ++> ui.profile_form { ProfileOut }
    manager ++> pages.index { list_profiles, create_profile, update_profile, delete_profile, duplicate_profile, reset_profile, launch_profile, stop_profile, system_status, get_settings, put_settings, list_files, delete_file }
    ui.profile_list ++> pages.index { ProfileList }
    ui.profile_form ++> pages.index { ProfileForm }
}
