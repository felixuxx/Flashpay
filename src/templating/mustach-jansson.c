/*
 Copyright (C) 2020 Taler Systems SA

 Original license:
 Author: José Bollo <jobol@nonadev.net>
 Author: José Bollo <jose.bollo@iot.bzh>

 https://gitlab.com/jobol/mustach

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

#include "platform.h"
#include "mustach-jansson.h"

struct Context
{
  /**
   * Context object.
   */
  json_t *cont;

  /**
   * Current object.
   */
  json_t *obj;

  /**
   * Opaque object iterator.
   */
  void *iter;

  /**
   * Current index when iterating over an array.
   */
  unsigned int index;

  /**
   * Count when iterating over an array.
   */
  unsigned int count;

  bool is_objiter;
};

enum Bang
{
  BANG_NONE,
  BANG_I18N,
  BANG_STRINGIFY,
  BANG_AMOUNT_CURRENCY,
  BANG_AMOUNT_DECIMAL,
};

struct JanssonClosure
{
  json_t *root;
  mustach_jansson_write_cb writecb;
  int depth;

  /**
   * Did the last find(..) call result in an iterable?
   */
  struct Context stack[MUSTACH_MAX_DEPTH];

  /**
   * The last object we found should be iterated over.
   */
  bool found_iter;

  /**
   * Last bang we found.
   */
  enum Bang found_bang;
  
  /**
   * Language for i18n lookups.
   */
  const char *lang;
};


static json_t *
walk (json_t *obj, const char *path)
{
  char *saveptr = NULL;
  char *sp = GNUNET_strdup (path);
  char *p = sp;
  while (true)
  {
    char *tok = strtok_r (p, ".", &saveptr);
    if (tok == NULL)
      break;
    obj = json_object_get (obj, tok);
    if (obj == NULL)
      break;
    p = NULL;
  }
  GNUNET_free (sp);
  return obj;
}


static json_t *
find (struct JanssonClosure *e, const char *name)
{
  json_t *obj = NULL;
  char *path = GNUNET_strdup (name);
  char *bang;

  bang = strchr (path, '!');

  e->found_bang = BANG_NONE;

  if (NULL != bang)
  {
    *bang = 0;
    bang++;

    if (0 == strcmp (bang, "i18n"))
      e->found_bang = BANG_I18N;
    else if (0 == strcmp(bang, "stringify"))
      e->found_bang = BANG_STRINGIFY;
    else if (0 == strcmp(bang, "amount_decimal"))
      e->found_bang = BANG_AMOUNT_CURRENCY;
    else if (0 == strcmp(bang, "amount_currency"))
      e->found_bang = BANG_AMOUNT_DECIMAL;
  }

  if (BANG_I18N == e->found_bang && NULL != e->lang)
  {
    char *aug_path;
    GNUNET_asprintf (&aug_path, "%s_i18n.%s", path, e->lang);
    obj = walk (e->stack[e->depth].obj, aug_path);
    GNUNET_free (aug_path);
  }

  if (NULL == obj)
  {
    obj = walk (e->stack[e->depth].obj, path);
  }

  GNUNET_free (path);

  return obj;
}


static int
start(void *closure)
{
  struct JanssonClosure *e = closure;
  e->depth = 0;
  e->stack[0].cont = NULL;
  e->stack[0].obj = e->root;
  e->stack[0].index = 0;
  e->stack[0].count = 1;
  e->lang = json_string_value (json_object_get (e->root, "$language"));
  return MUSTACH_OK;
}


static int
emituw (void *closure, const char *buffer, size_t size, int escape, FILE *file)
{
  struct JanssonClosure *e = closure;
  if (!escape)
    e->writecb (file, buffer, size);
  else
    do
    {
      switch (*buffer)
      {
        case '<':
          e->writecb (file, "&lt;", 4);
          break;
        case '>':
          e->writecb (file, "&gt;", 4);
          break;
        case '&':
          e->writecb (file, "&amp;", 5);
          break;
        default:
          e->writecb (file, buffer, 1);
          break;
      }
      buffer++;
    }
    while(--size);
  return MUSTACH_OK;
}


static int
enter(void *closure, const char *name)
{
  struct JanssonClosure *e = closure;
  json_t *o = find(e, name);
  if (++e->depth >= MUSTACH_MAX_DEPTH)
    return MUSTACH_ERROR_TOO_DEEP;

  if (json_is_object (o))
  {
    if (e->found_iter)
    {
      void *iter = json_object_iter (o);
      if (NULL == iter)
      {
        e->depth--;
        return 0;
      }
      e->stack[e->depth].is_objiter = 1;
      e->stack[e->depth].iter = iter;
      e->stack[e->depth].obj = json_object_iter_value (iter);
      e->stack[e->depth].cont = o;
    }
    else
    {
      e->stack[e->depth].is_objiter = 0;
      e->stack[e->depth].obj = o;
      e->stack[e->depth].cont = o;
    }
    return 1;
  }

  if (json_is_array (o))
  {
    unsigned int size = json_array_size (o);
    if (size == 0)
    {
      e->depth--;
      return 0;
    }
    e->stack[e->depth].count = size;
    e->stack[e->depth].cont = o;
    e->stack[e->depth].obj = json_array_get (o, 0);
    e->stack[e->depth].index = 0;
    e->stack[e->depth].is_objiter = 0;
    return 1;
  }

  e->depth--;
  return 0;
}


static int
next (void *closure)
{
  struct JanssonClosure *e = closure;
  struct Context *ctx;
  if (e->depth <= 0)
    return MUSTACH_ERROR_CLOSING;
  ctx = &e->stack[e->depth];
  if (ctx->is_objiter)
  {
    ctx->iter = json_object_iter_next (ctx->obj, ctx->iter);
    if (NULL == ctx->iter)
      return 0;
    ctx->obj = json_object_iter_value (ctx->iter);
    return 1;
  }
  ctx->index++;
  if (ctx->index >= ctx->count)
    return 0;
  ctx->obj = json_array_get (ctx->cont, ctx->index);
  return 1;
}

static int
leave (void *closure)
{
  struct JanssonClosure *e = closure;
  if (e->depth <= 0)
    return MUSTACH_ERROR_CLOSING;
  e->depth--;
  return 0;
}

static void
freecb (void *v)
{
  free (v);
}

static int
get (void *closure, const char *name, struct mustach_sbuf *sbuf)
{
  struct JanssonClosure *e = closure;
  json_t *obj;

  if ( (0 == strcmp (name, "*") ) &&
       (e->stack[e->depth].is_objiter ) )
  {
    sbuf->value = json_object_iter_key (e->stack[e->depth].iter);
    return MUSTACH_OK;
  }
  obj = find (e, name);
  if (NULL != obj)
  {
    switch (e->found_bang)
    {
      case BANG_I18N:
      case BANG_NONE:
        {
          const char *s = json_string_value (obj);
          if (NULL != s)
          {
            sbuf->value = s;
            return MUSTACH_OK;
          }
        }
        break;
      case BANG_STRINGIFY:
        sbuf->value = json_dumps (obj, JSON_INDENT (2));
        sbuf->freecb = freecb;
        return MUSTACH_OK;
      case BANG_AMOUNT_DECIMAL:
        {
          char *s;
          char *c;
          if (!json_is_string (obj))
            break;
          s = strdup (json_string_value (obj));
          c = strchr (s, ':');
          if (NULL != c)
            *c = 0;
          sbuf->value = s;
          sbuf->freecb = freecb;
          return MUSTACH_OK;
        }
        break;
      case BANG_AMOUNT_CURRENCY:
        {
          const char *s;
          if (!json_is_string (obj))
            break;
          s = json_string_value (obj);
          s = strchr (s, ':');
          if (NULL == s)
            break;
          sbuf->value = s + 1;
          return MUSTACH_OK;
        }
        break;
      default:
        break;
    }
  }
  sbuf->value = "";
  return MUSTACH_OK;
}

static struct mustach_itf itf = {
  .start = start,
  .put = NULL,
  .enter = enter,
  .next = next,
  .leave = leave,
  .partial =NULL,
  .get = get,
  .emit = NULL,
  .stop = NULL
};

static struct mustach_itf itfuw = {
  .start = start,
  .put = NULL,
  .enter = enter,
  .next = next,
  .leave = leave,
  .partial = NULL,
  .get = get,
  .emit = emituw,
  .stop = NULL
};

int fmustach_jansson (const char *template, json_t *root, FILE *file)
{
  struct JanssonClosure e = { 0 };
  e.root = root;
  return fmustach(template, &itf, &e, file);
}

int fdmustach_jansson (const char *template, json_t *root, int fd)
{
  struct JanssonClosure e = { 0 };
  e.root = root;
  return fdmustach(template, &itf, &e, fd);
}

int mustach_jansson (const char *template, json_t *root, char **result, size_t *size)
{
  struct JanssonClosure e = { 0 };
  e.root = root;
  e.writecb = NULL;
  return mustach(template, &itf, &e, result, size);
}

int umustach_jansson (const char *template, json_t *root, mustach_jansson_write_cb writecb, void *closure)
{
  struct JanssonClosure e = { 0 };
  e.root = root;
  e.writecb = writecb;
  return fmustach(template, &itfuw, &e, closure);
}

