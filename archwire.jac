graph layers {
    layer shared { model; util; }
    layer service { manager; }
}

graph spaces {
    space api: native { manager; }

    app manager { run api; }
}

graph import {
    edge Shared: shared --> service;

    model ++> manager { TagOut, ProfileOut, ArtifactOut, OkReply, ProfileReply, ProfilesReply, ArtifactReply, ArtifactsReply, FileReply, LaunchReply, StatusOut, SettingsOut, ConfigOut, AuthStatusOut }
    util ++> manager { safe_filename, mask_key, sidebar_width, data_dir }
}
