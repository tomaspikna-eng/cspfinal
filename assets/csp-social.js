/* Connect Sports Pro — shared likes and sharing for public content. */
(function (global) {
  'use strict';

  function element(value) {
    return typeof value === 'string' ? document.getElementById(value) : value;
  }

  async function getSession() {
    if (!global.cspAuth?.client) return null;
    const { data } = await global.cspAuth.client.auth.getSession();
    return data?.session || null;
  }

  function fallbackCopy(text) {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    const copied = document.execCommand('copy');
    area.remove();
    if (!copied) throw new Error('copy failed');
  }

  async function copy(text) {
    if (navigator.clipboard?.writeText && global.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }
    fallbackCopy(text);
  }

  async function share(options) {
    const payload = {
      title: options?.title || document.title,
      text: options?.text || '',
      url: options?.url || global.location.href
    };
    if (navigator.share) {
      try {
        await navigator.share(payload);
        return { shared: true, copied: false };
      } catch (error) {
        if (error?.name === 'AbortError') return { shared: false, copied: false, cancelled: true };
        // Some desktop browsers expose navigator.share but reject a valid
        // payload. Falling back to copy keeps the CTA useful there too.
      }
    }
    await copy(payload.url);
    return { shared: false, copied: true };
  }

  function loginRedirect() {
    const next = global.location.pathname + global.location.search + global.location.hash;
    global.location.href = '/login/?returnTo=' + encodeURIComponent(next);
  }

  async function bind(options) {
    const db = global.cspAuth?.client;
    const likeButton = element(options.likeButton);
    const likeCount = element(options.likeCount);
    const shareButton = element(options.shareButton);
    const entityType = String(options.entityType || '');
    const entityId = String(options.entityId || '');
    if (!db || !entityType || !entityId) return null;

    let session = await getSession();
    let liked = false;
    let busy = false;

    async function load() {
      const countQuery = db.from('social_reactions')
        .select('id', { count: 'exact', head: true })
        .eq('entity_type', entityType)
        .eq('entity_id', entityId)
        .eq('reaction_type', 'like');

      const ownQuery = session
        ? db.from('social_reactions').select('id')
            .eq('user_id', session.user.id)
            .eq('entity_type', entityType)
            .eq('entity_id', entityId)
            .eq('reaction_type', 'like')
            .maybeSingle()
        : Promise.resolve({ data: null, error: null });

      const [countResult, ownResult] = await Promise.all([countQuery, ownQuery]);
      if (countResult.error) throw countResult.error;
      if (ownResult.error) throw ownResult.error;
      liked = !!ownResult.data;
      if (likeCount) likeCount.textContent = String(countResult.count || 0);
      if (likeButton) {
        likeButton.classList.toggle('liked', liked);
        likeButton.setAttribute('aria-pressed', String(liked));
        const label = likeButton.querySelector('[data-like-label]');
        if (label) label.textContent = liked ? 'Páči sa mi' : 'Páči sa mi';
      }
      return { liked, count: countResult.count || 0 };
    }

    async function toggle() {
      if (busy) return;
      if (!session) {
        loginRedirect();
        return;
      }
      busy = true;
      if (likeButton) likeButton.disabled = true;
      try {
        let result;
        if (liked) {
          result = await db.from('social_reactions').delete()
            .eq('user_id', session.user.id)
            .eq('entity_type', entityType)
            .eq('entity_id', entityId)
            .eq('reaction_type', 'like');
        } else {
          result = await db.from('social_reactions').insert({
            user_id: session.user.id,
            entity_type: entityType,
            entity_id: entityId,
            reaction_type: 'like'
          });
        }
        if (result.error) throw result.error;
        await load();
        options.onLike?.({ liked });
      } catch (error) {
        console.error('[csp-social] like failed:', error);
        options.onError?.(error);
      } finally {
        busy = false;
        if (likeButton) likeButton.disabled = false;
      }
    }

    if (likeButton) likeButton.onclick = toggle;
    if (shareButton) {
      shareButton.onclick = async function () {
        try {
          const result = await share({ title: options.title, text: options.text, url: options.url });
          if (result.copied) options.onCopied?.();
        } catch (error) {
          console.error('[csp-social] share failed:', error);
          options.onError?.(error);
        }
      };
    }

    await load();
    return { reload: load, toggleLike: toggle };
  }

  global.cspSocial = { bind, share, copy };
})(window);
