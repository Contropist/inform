[Task::] What To Compile.

To receive an instruction to compile something from Inbuild, and then to
sort out the many locations then used in the host filing system.

@h Task data.
When Inbuild (a copy of which is included in the Inform 7 executable) decides
that an Inform source text must be compiled, it calls |Task::carry_out|. By
this point Inbuild will have set up an |inform_project| structure to
represent the program we have to compile; but we will need additional data
about that compilation, and it's stored in the following.

=
typedef struct compile_task_data {
	struct build_step *task;
	struct inform_project *project;
	
	struct pathname *path;
	struct pathname *materials;
	struct pathname *build;
	struct filename *existing_storyfile;
	
	int next_resource_number;

	MEMORY_MANAGEMENT
} compile_task_data;

@ An early and perhaps arguable design decision for inform7 was that it would
compile just one source text in its lifetime as a process: and because of that,
|Task::carry_out| can only in fact be called once, and Inbuild only does so
once. But the following routine allows in principle for multiple calls,
against the day when we change our minds about all this.

Something we will never do is attempt to make |inform7| thread-safe in the
sense of being able to compile two source texts simultaneously. The global
|inform7_task| is null when nothing is being compiled, or set to the unique
thing which is being compiled when it is.

=
compile_task_data *inform7_task = NULL;

int Task::carry_out(build_step *S) {
	inform_project *project = ProjectBundleManager::from_copy(S->associated_copy);
	if (project == NULL) project = ProjectFileManager::from_copy(S->associated_copy);
	if (project == NULL) internal_error("no project");

	if (inform7_task) internal_error("cannot re-enter with new task");
	inform7_task = CREATE(compile_task_data);
	inform7_task->task = S;
	inform7_task->project = project;
	inform7_task->path = S->associated_copy->location_if_path;
	inform7_task->build = Inbuild::transient();
	if (inform7_task->path)
		inform7_task->build = Pathnames::subfolder(inform7_task->path, I"Build");
	if (Pathnames::create_in_file_system(inform7_task->build) == 0) return FALSE;
	inform7_task->materials = Inbuild::materials();
	Task::set_existing_storyfile(NULL);
	inform7_task->next_resource_number = 3;

	inform_language *E = NaturalLanguages::English();
	Projects::set_language_of_syntax(project, E);
	Projects::set_language_of_index(project, E);
	Projects::set_language_of_play(project, E);

	int rv = Sequence::carry_out(inform7_task);
	inform7_task = NULL;
	return rv;
}

@ The current project and the virtual machine we want to compile it for:

=
inform_project *Task::project(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return inform7_task->project;
}

target_vm *Task::vm(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return inform7_task->task->for_vm;
}

@ Resources in a Blorb file have unique ID numbers which are positive integers,
but these are not required to start from 1, nor to be contiguous. For Inform,
ID number 1 is reserved for the cover image (whether or not any cover image
is provided: it is legal for there to be figures but no cover, and vice versa).
Other figures, and sound effects, then mix freely as needed from ID number 3
on upwards. We skip 2 so that it can be guaranteed that no sound resource
has ID 1 or 2: this is to help people trying to play sounds in the Z-machine,
where operand 1 or 2 in the |@sound| opcode signifies not a sound resource
number but a long or short beep. If a genuine sound effect had resource ID
1 or 2, therefore, it would be unplayable on the Z-machine.

=
int Task::get_next_free_blorb_resource_ID(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return inform7_task->next_resource_number++;
}

@ This seed is ordinarily 0, causing no fix to occur, but can be set to
a non-zero value to make testing Inform easier.

=
int Task::rng_seed(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return inform7_task->project->fix_rng;
}

@h Project-related files and file paths.
An Inform compilation can touch dozens of different files, and the rest
of this section is a tour through the ones which are associated with the
project itself. (Common resources, used for all compilations, or optional
add-ins such as extensions are the business of Inbuild.)

If a project is called, say, Wuthering Heights, and is a "bundle" as created
and compiled by the Inform app, then:

(a) The project path will be |Wuthering Heights.inform|. This looks opaque
on MacOS, as if a file, but on all platforms it is in fact a directory.
(b) Within it is |Wuthering Heights.inform/Build|, the "build folder".
(c) Alongside it is |Wuthering Heights.materials|. This is also a directory,
but is openly accessible even on MacOS.

If Inform is working on a single source text file, not a bundle, then the
project will be the current working directory, but now the build folder will
be the Inbuild transient area, and materials (if present) will again be
alongside.

To begin: what's in the project area? |story.ni| and |auto.inf|, neither
one very helpfully named, are defined in Inbuild rather than here: these
are the I7 source text and its compilation down to I6, respectively.
In addition we have:

The UUID file records an ISBN-like identifying number for the project. This
is read-only for us.

The iFiction record, manifest and blurb file are all files that we generate
to give instructions to the releasing agent Inblorb. This means that they
have no purpose unless Inform is in a release run (with |-release| set on
the command line), but they take no time to generate so we make them anyway.

=
filename *Task::uuid_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->path, I"uuid.txt");
}
filename *Task::ifiction_record_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->path, I"Metadata.iFiction");
}
filename *Task::manifest_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->path, I"manifest.plist");
}
filename *Task::blurb_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->path, I"Release.blurb");
}

@ The build folder for a project contains all of the working files created
during the compilation process. The debugging log and Inform problems report
(its HTML file of error messages) are both written there: see the Main Routine
section for details. In addition we have:

=
filename *Task::cblorb_report_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->build, I"StatusCblorb.html");
}
filename *Task::parse_tree_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->build, I"Parse tree.txt");
}

@ The name of the unblorbed story file is chosen for us by Inbuild, so
we have to extract it from the build graph:

=
filename *Task::storyfile_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	build_vertex *V = inform7_task->project->unblorbed_vertex;
	if (V == NULL) internal_error("project graph not ready");
	return V->buildable_if_internal_file;
}

@ Deeper inside the|Build| subfolder is an (also ephemeral) |Index| subfolder,
which holds the mini-website of the Index for a project.

The main index files (|Phrasebook.html| and so on) live at the top level,
details on actions live in the subfolder |Details|: see below.

=
pathname *Task::index_path(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	pathname *P = Pathnames::subfolder(inform7_task->build, I"Index");
	if (Pathnames::create_in_file_system(P)) return P;
	return NULL;
}

@ An oddity in the Index folder is an XML file recording where the headings
are in the source text: this is for the benefit of the user interface
application, if it wants it, but is not linked to or used by the HTML of
the index as seen by the user.

=
filename *Task::xml_headings_file(void) {
	return Filenames::in_folder(Task::index_path(), I"Headings.xml");
}

@ Within the Index is a deeper level, into the weeds as it were, called
|Details|.

=
pathname *Task::index_details_path(void) {
	pathname *P = Pathnames::subfolder(Task::index_path(), I"Details");
	if (Pathnames::create_in_file_system(P)) return P;
	return NULL;
}

@ And the following routine determines the filename for a page in this
mini-website. Filenames down in the |Details| area have the form
|N_S| where |N| is an integer supplied and |S| the leafname; for instance,
|21_A.html| provides details page number 21 about actions, derived from the
leafname |A.html|.

=
filename *Task::index_file(text_stream *leafname, int sub) {
	if (sub >= 0) {
		TEMPORARY_TEXT(full_leafname);
		WRITE_TO(full_leafname, "%d_%S", sub, leafname);
		filename *F = Filenames::in_folder(Task::index_details_path(), full_leafname);
		DISCARD_TEXT(full_leafname);
		return F;
	} else {
		return Filenames::in_folder(Task::index_path(), leafname);
	}
}

@ That's it for the project folder, but other project-related stuff is in
the materials folder, which we turn to next.

Inform is occasionally run in a mode where it performs a release on an
existing story file (for example a 1980s Infocom one) rather than on one
that it has newly generated. This is the filename such a story file would
have by default, if so.

By default the story file will be called something like |story.z8|, but
its leafname is actually declared from the source text of the Inform
project created to do this wrapping-up. So we need a way to set as well
as read this filename. Whatever the leafname, though, it lives in the top
level of materuals.

=
void Task::set_existing_storyfile(text_stream *name) {
	if (inform7_task == NULL) internal_error("there is no current task");
	if (name == NULL) {
		TEMPORARY_TEXT(leaf);
		WRITE_TO(leaf, "story.%S", TargetVMs::get_unblorbed_extension(Task::vm()));
		inform7_task->existing_storyfile = Filenames::in_folder(inform7_task->materials, leaf);
		DISCARD_TEXT(leaf);
	} else {
		inform7_task->existing_storyfile = Filenames::in_folder(inform7_task->materials, name);
	}
}
filename *Task::existing_storyfile_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return inform7_task->existing_storyfile;
}

@ Materials is also where cover art lives: it could have either the file
extension |.jpg| or |.png|, and we generate both sets of filenames, even
though at most one will actually work. This is also where we generate the EPS
file of the map, if so requested; a bit anomalously, it's the only file in
Materials but outside Release which we write to.

This is also where the originals (not the released copies) of the Figures
and Sounds, if any, live: in their own subfolders.

=
filename *Task::large_cover_art_file(int JPEG) {
	if (inform7_task == NULL) internal_error("there is no current task");
	if (JPEG) return Filenames::in_folder(inform7_task->materials, I"Cover.jpg");
	return Filenames::in_folder(inform7_task->materials, I"Cover.png");
}
filename *Task::epsmap_file(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Filenames::in_folder(inform7_task->materials, I"Inform Map.eps");
}

pathname *Task::figures_path(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Pathnames::subfolder(inform7_task->materials, I"Figures");
}
pathname *Task::sounds_path(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Pathnames::subfolder(inform7_task->materials, I"Sounds");
}

@ On a release run, Inblorb will populate the Release subfolder of Materials;
figures and sounds will be copied into the relevant subfolders. The principle
is that everything in Release can always be thrown away without loss, because
it can all be generated again.

=
pathname *Task::release_path(void) {
	if (inform7_task == NULL) internal_error("there is no current task");
	return Pathnames::subfolder(inform7_task->materials, I"Release");
}
pathname *Task::released_figures_path(void) {
	return Pathnames::subfolder(Task::release_path(), I"Figures");
}
pathname *Task::released_sounds_path(void) {
	return Pathnames::subfolder(Task::release_path(), I"Sounds");
}
pathname *Task::released_interpreter_path(void) {
	return Pathnames::subfolder(Task::release_path(), I"interpreter");
}