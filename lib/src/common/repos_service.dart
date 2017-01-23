part of github.common;

/// The [RepositoriesService] handles communication with repository related
/// methods of the GitHub API.
///
/// API docs: https://developer.github.com/v3/repos/
class RepositoriesService extends Service {
  RepositoriesService(GitHub github) : super(github);

  /// Lists the repositories of the currently authenticated user.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-your-repositories
  Stream<Repository> listRepositories(
      {String type: "owner",
      String sort: "full_name",
      String direction: "asc"}) {
    var params = {"type": type, "sort": sort, "direction": direction};

    return new PaginationHelper(_github)
            .objects("GET", "/user/repos", Repository.fromJSON, params: params)
        as Stream<Repository>;
  }

  /// Lists the repositories of the user specified by [user] in a streamed fashion.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-user-repositories
  Stream<Repository> listUserRepositories(String user,
      {String type: "owner",
      String sort: "full_name",
      String direction: "asc"}) {
    var params = {"type": type, "sort": sort, "direction": direction};

    return new PaginationHelper(_github).objects(
            "GET", "/users/${user}/repos", Repository.fromJSON, params: params)
        as Stream<Repository>;
  }

  /// List repositories for the specified [org].
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-user-repositories
  Stream<Repository> listOrganizationRepositories(String org,
      {String type: "all"}) {
    var params = {
      "type": type,
    };

    return new PaginationHelper(_github).objects(
            "GET", "/orgs/${org}/repos", Repository.fromJSON, params: params)
        as Stream<Repository>;
  }

  /// Lists all the public repositories on GitHub, in the order that they were
  /// created.
  ///
  /// If [limit] is not null, it is used to specify the amount of repositories to fetch.
  /// If [limit] is null, it will fetch ALL the repositories on GitHub.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-all-public-repositories
  Stream<Repository> listPublicRepositories({int limit: 50, DateTime since}) {
    var params = <String, String>{};

    if (since != null) {
      params['since'] = since.toIso8601String();
    }

    var pages = limit != null ? (limit / 30).ceil() : null;

    // TODO: Close this, but where?
    var controller = new StreamController<Repository>.broadcast();

    new PaginationHelper(_github)
        .fetchStreamed("GET", "/repositories", pages: pages, params: params)
        .listen((http.Response response) {
      var list = JSON.decode(response.body);
      var repos = new List.from(
          list.map((Map<String, dynamic> it) => Repository.fromJSON(it)));
      for (var repo in repos) controller.add(repo);
    });

    return controller.stream.take(limit);
  }

  /// Creates a repository with [repository]. If an [org] is specified, the new
  /// repository will be created under that organization. If no [org] is
  /// specified, it will be created for the authenticated user.
  ///
  /// API docs: https://developer.github.com/v3/repos/#create
  Future<Repository> createRepository(CreateRepository repository,
      {String org}) {
    if (org != null) {
      return _github.postJSON('/orgs/${org}/repos',
          body: repository.toJSON(),
          convert: TeamRepository.fromJSON) as Future<Repository>;
    } else {
      return _github.postJSON('/user/repos',
          body: repository.toJSON(),
          convert: Repository.fromJSON) as Future<Repository>;
    }
  }

  /// Fetches the repository specified by the [slug].
  ///
  /// API docs: https://developer.github.com/v3/repos/#get
  Future<Repository> getRepository(RepositorySlug slug) {
    return _github.getJSON("/repos/${slug.owner}/${slug.name}",
        convert: Repository.fromJSON,
        statusCode: StatusCodes.OK, fail: (http.Response response) {
      if (response.statusCode == 404) {
        throw new RepositoryNotFound(_github, slug.fullName);
      }
    }) as Future<Repository>;
  }

  /// Fetches a list of repositories specified by [slugs].
  Stream<Repository> getRepositories(List<RepositorySlug> slugs) {
    var controller = new StreamController<Repository>();

    var group = new FutureGroup();

    for (var slug in slugs) {
      group.add(getRepository(slug).then((repo) {
        controller.add(repo);
      }));
    }

    group.future.then((_) {
      controller.close();
    });

    return controller.stream;
  }

  /// Edit a Repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#edit
  Future<Repository> editRepository(RepositorySlug repo,
      {String name,
      String description,
      String homepage,
      bool private,
      bool hasIssues,
      bool hasWiki,
      bool hasDownloads}) {
    var data = createNonNullMap({
      "name": name,
      "description": description,
      "homepage": homepage,
      "private": private,
      "has_issues": hasIssues,
      "has_wiki": hasWiki,
      "has_downloads": hasDownloads,
      "default_branch": "defaultBranch"
    });
    return _github.postJSON("/repos/${repo.fullName}",
        // TODO: data probably needs to be json encoded?
        body: data,
        statusCode: 200) as Future<Repository>;
  }

  /// Deletes a repository.
  ///
  /// Returns true if it was successfully deleted.
  ///
  /// API docs: https://developer.github.com/v3/repos/#delete-a-repository
  Future<bool> deleteRepository(RepositorySlug slug) {
    return _github
        .request('DELETE', '/repos/${slug.fullName}')
        .then((response) => response.statusCode == StatusCodes.NO_CONTENT);
  }

  /// Lists the contributors of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-contributors
  Stream<Tag> listContributors(RepositorySlug slug, {bool anon: false}) {
    return new PaginationHelper(_github).objects(
        'GET', '/repos/${slug.fullName}/contributors', User.fromJSON,
        params: {"anon": anon.toString()}) as Stream<Tag>;
  }

  /// Lists the teams of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-teams
  Stream<Team> listTeams(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
        'GET', '/repos/${slug.fullName}/teams', Team.fromJSON) as Stream<Team>;
  }

  /// Gets a language breakdown for the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-languages
  Future<LanguageBreakdown> listLanguages(RepositorySlug slug) =>
      _github.getJSON("/repos/${slug.fullName}/languages",
          statusCode: StatusCodes.OK,
          convert: (Map<String, int> input) => new LanguageBreakdown(input))
      as Future<LanguageBreakdown>;

  /// Lists the tags of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-tags
  Stream<Tag> listTags(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
        'GET', '/repos/${slug.fullName}/tags', Tag.fromJSON) as Stream<Tag>;
  }

  /// Lists the branches of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/#list-branches
  Stream<Branch> listBranches(RepositorySlug slug) {
    return new PaginationHelper(_github)
            .objects('GET', '/repos/${slug.fullName}/branches', Branch.fromJSON)
        as Stream<Branch>;
  }

  /// Fetches the specified branch.
  ///
  /// API docs: https://developer.github.com/v3/repos/#get-branch
  Future<Branch> getBranch(RepositorySlug slug, String branch) {
    return _github.getJSON("/repos/${slug.fullName}/branches/${branch}",
        convert: Branch.fromJSON) as Future<Branch>;
  }

  /// Lists the users that have access to the repository identified by [slug].
  ///
  /// API docs: https://developer.github.com/v3/repos/collaborators/#list
  Stream<User> listCollaborators(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
            "GET", "/repos/${slug.fullName}/collaborators", User.fromJSON)
        as Stream<User>;
  }

  Future<bool> isCollaborator(RepositorySlug slug, String user) {
    return _github
        .request("GET", "/repos/${slug.fullName}/collaborators/${user}")
        .then((response) {
      return response.statusCode == 204;
    });
  }

  Future<bool> addCollaborator(RepositorySlug slug, String user) {
    return _github
        .request("PUT", "/repos/${slug.fullName}/collaborators/${user}")
        .then((response) {
      return response.statusCode == 204;
    });
  }

  Future<bool> removeCollaborator(RepositorySlug slug, String user) {
    return _github
        .request("DELETE", "/repos/${slug.fullName}/collaborators/${user}")
        .then((response) {
      return response.statusCode == 204;
    });
  }

  // TODO: Implement listComments: https://developer.github.com/v3/repos/comments/#list-commit-comments-for-a-repository
  // TODO: Implement listCommitComments: https://developer.github.com/v3/repos/comments/#list-comments-for-a-single-commit
  // TODO: Implement createComment: https://developer.github.com/v3/repos/comments/#create-a-commit-comment
  // TODO: Implement getComment: https://developer.github.com/v3/repos/comments/#get-a-single-commit-comment
  // TODO: Implement updateComment: https://developer.github.com/v3/repos/comments/#update-a-commit-comment
  // TODO: Implement deleteComment: https://developer.github.com/v3/repos/comments/#delete-a-commit-comment

  /// Lists the commits of the provided repository [slug].
  ///
  /// API docs: https://developer.github.com/v3/repos/commits/#list-commits-on-a-repository
  Stream<RepositoryCommit> listCommits(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
            "GET", "/repos/${slug.fullName}/commits", RepositoryCommit.fromJSON)
        as Stream<RepositoryCommit>;
  }

  /// Fetches the specified commit.
  ///
  /// API docs: https://developer.github.com/v3/repos/commits/#get-a-single-commit
  Future<RepositoryCommit> getCommit(RepositorySlug slug, String sha) {
    return _github.getJSON("/repos/${slug.fullName}/commits/${sha}",
        convert: RepositoryCommit.fromJSON) as Future<RepositoryCommit>;
  }

  // TODO: Implement compareCommits: https://developer.github.com/v3/repos/commits/#compare-two-commits

  /// Fetches the readme file for a repository.
  ///
  /// The name of the commit/branch/tag may be specified with [ref]. If no [ref]
  /// is defined, the repository's default branch is used (usually master).
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#get-the-readme
  Future<GitHubFile> getReadme(RepositorySlug slug, {String ref}) {
    var headers = <String, String>{};

    String url = "/repos/${slug.fullName}/readme";

    if (ref != null) {
      url += '?ref=$ref';
    }

    return _github.getJSON(url, headers: headers, statusCode: StatusCodes.OK,
        fail: (http.Response response) {
      if (response.statusCode == 404) {
        throw new NotFound(_github, response.body);
      }
    },
        convert: (Map<String, dynamic> input) =>
            GitHubFile.fromJSON(input, slug)) as Future<GitHubFile>;
  }

  /// Fetches content in a repository at the specified [path].
  ///
  /// When the [path] references a file, the returned [RepositoryContents]
  /// contains the metadata AND content of a single file.
  ///
  /// When the [path] references a directory, the returned [RepositoryContents]
  /// contains the metadata of all the files and/or subdirectories.
  ///
  /// Use [RepositoryContents.isFile] or [RepositoryContents.isDirectory] to
  /// distinguish between both result types.
  ///
  /// The name of the commit/branch/tag may be specified with [ref]. If no [ref]
  /// is defined, the repository's default branch is used (usually master).
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#get-contents
  Future<RepositoryContents> getContents(RepositorySlug slug, String path,
      {String ref}) {
    String url = "/repos/${slug.fullName}/contents/${path}";

    if (ref != null) {
      url += '?ref=$ref';
    }

    return _github.getJSON(url, convert: (input) {
      var contents = new RepositoryContents();
      if (input is Map) {
        contents.file = GitHubFile.fromJSON(input as Map<String, dynamic>);
      } else {
        contents.tree = (input as List<Map<String, dynamic>>)
            .map((Map<String, dynamic> it) => GitHubFile.fromJSON(it))
            .toList();
      }
      return contents;
    }) as Future<RepositoryContents>;
  }

  /// Creates a new file in a repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#create-a-file
  Future<ContentCreation> createFile(RepositorySlug slug, CreateFile file) {
    return _github
        .request("PUT", "/repos/${slug.fullName}/contents/${file.path}",
            body: file.toJSON())
        .then((response) {
      return ContentCreation
          .fromJSON(JSON.decode(response.body) as Map<String, dynamic>);
    });
  }

  /// Updates the specified file.
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#update-a-file
  Future<ContentCreation> updateFile(RepositorySlug slug, String path,
      String message, String content, String sha,
      {String branch}) {
    var map = createNonNullMap(
        {"message": message, "content": content, "sha": sha, "branch": branch});

    return _github.postJSON("/repos/${slug.fullName}/contents/${path}",
        // TODO: map probably needs to be json encoded
        body: map,
        statusCode: 200,
        convert: ContentCreation.fromJSON) as Future<ContentCreation>;
  }

  /// Deletes the specified file.
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#delete-a-file
  Future<ContentCreation> deleteFile(RepositorySlug slug, String path,
      String message, String sha, String branch) {
    var map =
        createNonNullMap({"message": message, "sha": sha, "branch": branch});

    return _github
        .request("DELETE", "/repos/${slug.fullName}/contents/${path}",
            body: JSON.encode(map), statusCode: 200)
        .then((response) {
      return ContentCreation
          .fromJSON(JSON.decode(response.body) as Map<String, dynamic>);
    });
  }

  /// Gets an archive link for the specified repository and reference.
  ///
  /// API docs: https://developer.github.com/v3/repos/contents/#get-archive-link
  Future<String> getArchiveLink(RepositorySlug slug, String ref,
      {String format: "tarball"}) {
    return _github
        .request("GET", "/repos/${slug.fullName}/${format}/${ref}",
            statusCode: 302)
        .then((response) {
      return response.headers["Location"];
    });
  }

  /// Lists the forks of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/forks/#list-forks
  Stream<Repository> listForks(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
            "GET", "/repos/${slug.fullName}/forks", Repository.fromJSON)
        as Stream<Repository>;
  }

  /// Creates a fork for the authenticated user.
  ///
  /// API docs: https://developer.github.com/v3/repos/forks/#create-a-fork
  Future<Repository> createFork(RepositorySlug slug, [CreateFork fork]) {
    if (fork == null) fork = new CreateFork();
    return _github.postJSON("/repos/${slug.fullName}/forks",
        body: fork.toJSON(),
        convert: Repository.fromJSON) as Future<Repository>;
  }

  /// Lists the hooks of the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/hooks/#list-hooks
  Stream<Hook> listHooks(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
            "GET",
            "/repos/${slug.fullName}/hooks",
            (Map<String, dynamic> input) => Hook.fromJSON(slug.fullName, input))
        as Stream<Hook>;
  }

  /// Fetches a single hook by [id].
  ///
  /// API docs: https://developer.github.com/v3/repos/hooks/#get-single-hook
  Future<Hook> getHook(RepositorySlug slug, int id) {
    return _github.getJSON("/repos/${slug.fullName}/hooks/${id}",
        convert: (Map<String, dynamic> i) =>
            Hook.fromJSON(slug.fullName, i)) as Future<Hook>;
  }

  /// Creates a repository hook based on the specified [hook].
  ///
  /// API docs: https://developer.github.com/v3/repos/hooks/#create-a-hook
  Future<Hook> createHook(RepositorySlug slug, CreateHook hook) {
    return _github.postJSON("/repos/${slug.fullName}/hooks",
        convert: (Map<String, dynamic> i) => Hook.fromJSON(slug.fullName, i),
        body: hook.toJSON()) as Future<Hook>;
  }

  // TODO: Implement editHook: https://developer.github.com/v3/repos/hooks/#edit-a-hook

  /// Triggers a hook with the latest push.
  ///
  /// API docs: https://developer.github.com/v3/repos/hooks/#test-a-push-hook
  Future<bool> testPushHook(RepositorySlug slug, int id) {
    return _github
        .request("POST", "/repos/${slug.fullName}/hooks/${id}/tests")
        .then((response) => response.statusCode == 204);
  }

  /// Pings the hook.
  ///
  /// API docs: https://developer.github.com/v3/repos/hooks/#ping-a-hook
  Future<bool> pingHook(RepositorySlug slug, int id) {
    return _github
        .request("POST", "/repos/${slug.fullName}/hooks/${id}/pings")
        .then((response) => response.statusCode == 204);
  }

  Future<bool> deleteHook(RepositorySlug slug, int id) {
    return _github
        .request("DELETE", "/repos/${slug.fullName}/hooks/${id}")
        .then((response) {
      return response.statusCode == 204;
    });
  }

  // TODO: Implement other hook methods: https://developer.github.com/v3/repos/hooks/

  /// Lists the deploy keys for a repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/keys/#list
  Stream<PublicKey> listDeployKeys(RepositorySlug slug) {
    return new PaginationHelper(_github)
            .objects("GET", "/repos/${slug.fullName}/keys", PublicKey.fromJSON)
        as Stream<PublicKey>;
  }

  // TODO: Implement getDeployKey: https://developer.github.com/v3/repos/keys/#get

  /// Adds a deploy key for a repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/keys/#create
  Future<PublicKey> createDeployKey(RepositorySlug slug, CreatePublicKey key) {
    return _github.postJSON("/repos/${slug.fullName}/keys", body: key.toJSON())
        as Future<PublicKey>;
  }

  // TODO: Implement editDeployKey: https://developer.github.com/v3/repos/keys/#edit
  // TODO: Implement deleteDeployKey: https://developer.github.com/v3/repos/keys/#delete

  /// Merges a branch in the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/merging/#perform-a-merge
  Future<RepositoryCommit> merge(RepositorySlug slug, CreateMerge merge) {
    return _github.postJSON("/repos/${slug.fullName}/merges",
        body: merge.toJSON(),
        convert: RepositoryCommit.fromJSON,
        statusCode: 201) as Future<RepositoryCommit>;
  }

  /// Fetches the GitHub pages information for the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/pages/#get-information-about-a-pages-site
  Future<RepositoryPages> getPagesInfo(RepositorySlug slug) {
    return _github.getJSON("/repos/${slug.fullName}/pages",
        statusCode: 200,
        convert: RepositoryPages.fromJSON) as Future<RepositoryPages>;
  }

  // TODO: Implement listPagesBuilds: https://developer.github.com/v3/repos/pages/#list-pages-builds
  // TODO: Implement getLatestPagesBuild: https://developer.github.com/v3/repos/pages/#list-latest-pages-build

  /// Lists releases for the specified repository.
  ///
  /// API docs: https://developer.github.com/v3/repos/releases/#list-releases-for-a-repository
  Stream<Release> listReleases(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
            "GET", "/repos/${slug.fullName}/releases", Release.fromJSON)
        as Stream<Release>;
  }

  /// Fetches a single release.
  ///
  /// API docs: https://developer.github.com/v3/repos/releases/#get-a-single-release
  Future<Release> getRelease(RepositorySlug slug, int id) {
    return _github.getJSON("/repos/${slug.fullName}/releases/${id}",
        convert: Release.fromJSON) as Future<Release>;
  }

  /// Creates a Release based on the specified [release].
  ///
  /// API docs: https://developer.github.com/v3/repos/releases/#create-a-release
  Future<Hook> createRelease(RepositorySlug slug, CreateRelease release) {
    return _github.postJSON("/repos/${slug.fullName}/releases",
        convert: Release.fromJSON, body: release.toJSON()) as Future<Hook>;
  }

  // TODO: Implement editRelease: https://developer.github.com/v3/repos/releases/#edit-a-release
  // TODO: Implement deleteRelease: https://developer.github.com/v3/repos/releases/#delete-a-release
  // TODO: Implement listReleaseAssets: https://developer.github.com/v3/repos/releases/#list-assets-for-a-release
  // TODO: Implement getReleaseAssets: https://developer.github.com/v3/repos/releases/#get-a-single-release-asset
  // TODO: Implement editReleaseAssets: https://developer.github.com/v3/repos/releases/#edit-a-release-asset
  // TODO: Implement deleteReleaseAssets: https://developer.github.com/v3/repos/releases/#delete-a-release-asset
  // TODO: Implement uploadReleaseAsset: https://developer.github.com/v3/repos/releases/#upload-a-release-asset

  /// Lists repository contributor statistics.
  ///
  /// API docs: https://developer.github.com/v3/repos/statistics/#contributors
  Future<List<ContributorStatistics>> listContributorStats(RepositorySlug slug,
      {int limit: 30}) {
    var completer = new Completer<List<ContributorStatistics>>();
    var path = "/repos/${slug.fullName}/stats/contributors";
    var handle;
    handle = (json) {
      if (json is Map) {
        new Future.delayed(new Duration(milliseconds: 200), () {
          _github.getJSON(path,
              statusCode: 200,
              convert: handle,
              params: {"per_page": limit.toString()});
        });
        return null;
      } else {
        completer.complete(json.map(
            (Map<String, dynamic> it) => ContributorStatistics.fromJSON(it)));
      }
    };
    _github
        .getJSON(path, convert: handle, params: {"per_page": limit.toString()});
    return completer.future;
  }

  /// Fetches commit counts for the past year.
  ///
  /// API docs: https://developer.github.com/v3/repos/statistics/#commit-activity
  Stream<YearCommitCountWeek> listCommitActivity(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
        "GET",
        "/repos/${slug.fullName}/stats/commit_activity",
        YearCommitCountWeek.fromJSON) as Stream<YearCommitCountWeek>;
  }

  /// Fetches weekly addition and deletion counts.
  ///
  /// API docs: https://developer.github.com/v3/repos/statistics/#code-frequency
  Stream<WeeklyChangesCount> listCodeFrequency(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
        "GET",
        "/repos/${slug.fullName}/stats/code_frequency",
        WeeklyChangesCount.fromJSON) as Stream<WeeklyChangesCount>;
  }

  /// Fetches Participation Breakdowns.
  ///
  /// API docs: https://developer.github.com/v3/repos/statistics/#participation
  Future<ContributorParticipation> getParticipation(RepositorySlug slug) {
    return _github.getJSON("/repos/${slug.fullName}/stats/participation",
            statusCode: 200, convert: ContributorParticipation.fromJSON)
        as Future<ContributorParticipation>;
  }

  /// Fetches Punchcard.
  ///
  /// API docs: https://developer.github.com/v3/repos/statistics/#punch-card
  Stream<PunchcardEntry> listPunchcard(RepositorySlug slug) {
    return new PaginationHelper(_github).objects(
        "GET",
        "/repos/${slug.fullName}/stats/punchcard",
        PunchcardEntry.fromJSON) as Stream<PunchcardEntry>;
  }

  /// Lists the statuses of a repository at the specified reference.
  /// The [ref] can be a SHA, a branch name, or a tag name.
  ///
  /// API docs: https://developer.github.com/v3/repos/statuses/#list-statuses-for-a-specific-ref
  Stream<RepositoryStatus> listStatuses(RepositorySlug slug, String ref) {
    return new PaginationHelper(_github).objects(
        "GET",
        "/repos/${slug.fullName}/commits/${ref}/statuses",
        RepositoryStatus.fromJSON) as Stream<RepositoryStatus>;
  }

  /// Creates a new status for a repository at the specified reference.
  /// The [ref] can be a SHA, a branch name, or a tag name.
  ///
  /// API docs: https://developer.github.com/v3/repos/statuses/#create-a-status
  Future<RepositoryStatus> createStatus(
      RepositorySlug slug, String ref, CreateStatus request) {
    return _github.postJSON("/repos/${slug.fullName}/statuses/${ref}",
        body: request.toJSON(),
        convert: RepositoryStatus.fromJSON) as Future<RepositoryStatus>;
  }

  /// Gets a Combined Status for the specified repository and ref.
  ///
  /// API docs: https://developer.github.com/v3/repos/statuses/#get-the-combined-status-for-a-specific-ref
  Future<CombinedRepositoryStatus> getCombinedStatus(
      RepositorySlug slug, String ref) {
    return _github.getJSON("/repos/${slug.fullName}/commits/${ref}/status",
        convert: CombinedRepositoryStatus.fromJSON,
        statusCode: 200) as Future<CombinedRepositoryStatus>;
  }
}
