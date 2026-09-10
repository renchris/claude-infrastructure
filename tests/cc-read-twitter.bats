#!/usr/bin/env bats
#
# bin/cc-read-twitter — reads an X/Twitter post or thread from a URL.
#
# Almost every test here is OFFLINE: it imports the script as a module and
# exercises the pure functions. The network arms are gated on CC_RT_NET=1 so a
# suite run never depends on a third party being up — a network flake must not
# be able to redden this file.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TOOL="$REPO/bin/cc-read-twitter"
  # Fixture HOME and TMPDIR: --images writes under TMPDIR, and nothing here may
  # touch the operator's live ~/ or collide with a concurrent run.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}

# Load the extensionless script as a python module.
py() {
  python3 - "$TOOL" "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_loader(
    "rt", importlib.machinery.SourceFileLoader("rt", sys.argv[1]))
rt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rt)
exec(sys.argv[2])
PY
}

@test "fixture honesty: the tool exists and is executable, so nothing below passes vacuously" {
  [ -f "$TOOL" ]
  [ -x "$TOOL" ]
  run python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$TOOL"
  [ "$status" -eq 0 ]
}

@test "parse_id accepts every URL shape X actually serves" {
  for u in \
    "https://x.com/AnthropicAI/status/2070528969523499460" \
    "https://twitter.com/AnthropicAI/status/2070528969523499460" \
    "https://x.com/i/status/2070528969523499460" \
    "https://x.com/i/web/status/2070528969523499460" \
    "https://x.com/u/status/2070528969523499460?s=20&t=abc" \
    "https://fxtwitter.com/u/status/2070528969523499460" \
    "2070528969523499460" ; do
    run py "print(rt.parse_id('$u'))"
    [ "$status" -eq 0 ]
    [ "$output" = "2070528969523499460" ]
  done
}

@test "parse_id refuses a non-status input rather than guessing" {
  run "$TOOL" "https://x.com/AnthropicAI"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot find a status id"* ]]
}

@test "syndication_token is deterministic and strips '0' and '.' as the embed client does" {
  run py "t=rt.syndication_token('2070528969523499460'); print(t); assert '0' not in t and '.' not in t; assert t==rt.syndication_token('2070528969523499460')"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "size_url makes the printed URL and the downloaded URL agree" {
  # A reader who curls the printed URL must get the bytes --images would fetch.
  run py "print(rt.size_url('https://pbs.twimg.com/media/X.png?name=orig'))"
  [ "$output" = "https://pbs.twimg.com/media/X.png?name=medium" ]
  run py "print(rt.size_url('https://pbs.twimg.com/media/X.png'))"
  [ "$output" = "https://pbs.twimg.com/media/X.png?name=medium" ]
  run py "print(rt.size_url('https://pbs.twimg.com/media/X?format=jpg'))"
  [ "$output" = "https://pbs.twimg.com/media/X?format=jpg&name=medium" ]
}

@test "pick_video caps the ladder instead of taking the top rung" {
  # media.videos[0].url is the 4K/25Mbps variant — ~120MB for a 38s clip.
  run py "
m={'url':'https://v/top.mp4','variants':[
 {'url':'https://v/vid/avc1/480x270/a.mp4','bitrate':256000},
 {'url':'https://v/vid/avc1/1280x720/b.mp4','bitrate':2176000},
 {'url':'https://v/vid/avc1/1920x1080/c.mp4','bitrate':10368000},
 {'url':'https://v/x.m3u8'}]}
print(rt.pick_video(m))"
  [ "$output" = "https://v/vid/avc1/1280x720/b.mp4" ]
}

@test "pick_video degrades to the bare url when no variant carries dimensions" {
  run py "print(rt.pick_video({'url':'https://v/only.mp4','variants':[]}))"
  [ "$output" = "https://v/only.mp4" ]
}

@test "a truncated long post is flagged, never rendered as if complete" {
  run py "
p=dict(id='1',author='a',author_name='A',created_at='t',text='cut',truncated=True,media=[],
 likes=None,replies=None,reposts=None,views=None,replying_to=None,quote=None,
 community_note=None,poll=None,article=None,url='u')
print(rt.render([p],{'source':'syndication'},{}))"
  [[ "$output" == *"TRUNCATED"* ]]
}

@test "an article with no body blocks says 'preview only' rather than passing the teaser off as the article" {
  run py "
print('\n'.join(rt.render_article({'title':'T','preview_text':'teaser','content':{}})))"
  [[ "$output" == *"preview only"* ]]
}

@test "article images survive the two-hop draft.js join (block -> entityMap -> media_entities)" {
  # entityMap is a LIST of {key,value} with STRING keys while the block's
  # entityRanges[0].key is an INT — a naive dict index silently drops every image.
  run py "
art={'title':'T','content':{
 'blocks':[{'type':'atomic','text':'','entityRanges':[{'key':4}]}],
 'entityMap':[{'key':'4','value':{'type':'MEDIA','data':{'caption':'Fig 1','mediaItems':[{'mediaId':'m1'}]}}}]},
 'media_entities':[{'media_id':'m1','media_info':{'original_img_url':'https://pbs/i.jpg'}}]}
print('\n'.join(rt.render_article(art)))"
  [[ "$output" == *"https://pbs/i.jpg"* ]] || false
  [[ "$output" == *"Fig 1"* ]] || false
}

@test "article_images finds the cover AND the body figures — neither is in media[]" {
  # The defect this pins: --images keyed only on posts[].media, so an X Article
  # post (media == []) downloaded NOTHING and said nothing was missing. The
  # cover hangs off cover_media; the figures need the two-hop entityMap join.
  run py "
art={'title':'T',
 'cover_media':{'media_info':{'original_img_url':'https://pbs/cover.jpg'}},
 'content':{'blocks':[{'type':'atomic','text':'','entityRanges':[{'key':4}]}],
  'entityMap':[{'key':'4','value':{'type':'MEDIA','data':{'caption':'Fig 1','mediaItems':[{'mediaId':'m1'}]}}}]},
 'media_entities':[{'media_id':'m1','media_info':{'original_img_url':'https://pbs/fig.jpg'}}]}
ims=rt.article_images(art)
print(len(ims), ims[0]['url'], ims[0]['caption'], ims[1]['url'])"
  [[ "$output" == "2 https://pbs/cover.jpg cover https://pbs/fig.jpg" ]] || false
}

@test "article_images is empty, not exploded, on a post with no article" {
  run py "print(len(rt.article_images({})))"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "an article post renders its cover, which lives outside the body blocks" {
  run py "
art={'title':'T','cover_media':{'media_info':{'original_img_url':'https://pbs/cover.jpg'}},
 'content':{'blocks':[{'type':'unstyled','text':'body'}],'entityMap':[]}}
print('\n'.join(rt.render_article(art)))"
  [[ "$output" == *"cover"* ]] || false
  [[ "$output" == *"https://pbs/cover.jpg"* ]]
}

@test "--help exits clean" {
  run "$TOOL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--images"* ]]
}

@test "NETWORK: a real thread renders in both directions from a middle post" {
  [ "${CC_RT_NET:-0}" = "1" ] || skip "set CC_RT_NET=1 to run network arms"
  run "$TOOL" 2070528969523499460
  [ "$status" -eq 0 ]
  # the true root, three hops above the linked post's own stated parent...
  [[ "$output" == *"2070528961235575278"* ]] || false
  # ...and a self-reply BELOW the linked post.
  [[ "$output" == *"2070528971687755796"* ]]
}

@test "NETWORK: a dead id fails loudly on every rung instead of returning an empty post" {
  [ "${CC_RT_NET:-0}" = "1" ] || skip "set CC_RT_NET=1 to run network arms"
  run "$TOOL" 1234567890123456789
  [ "$status" -eq 3 ]
  [[ "$output" == *"every source declined"* ]]
}
