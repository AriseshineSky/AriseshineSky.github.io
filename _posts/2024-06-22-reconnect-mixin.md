---
layout: post
title: Reconnect
categories: [http]
description: 
keywords: 
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---

# Mysql Reconnect

1. Python 2 `__metaclass__`    
    1.1. To manipulate a class before it is created by overriding `__new__` method
2. object.`__new__`    
    2.1. Called to create a new instance of class *cls*. `__new__` is a static method that takes the class of which an instance was requested as its first argument. The remaining arguments are those passed to the object constructor expression. The return value of `__new__`() should be the new object instance.  
```
class ReconnectMixin(object):
    """
    Mixin class that attempts to automatically reconnect to the database under
    certain error conditions.

    For example, MySQL servers will typically close connections that are idle
    for 28800 seconds ("wait_timeout" setting). If your application makes use
    of long-lived connections, you may find your connections are closed after
    a period of no activity. This mixin will attempt to reconnect automatically
    when these errors occur.

    This mixin class probably should not be used with Postgres (unless you
    REALLY know what you are doing) and definitely has no business being used
    with Sqlite. If you wish to use with Postgres, you will need to adapt the
    `reconnect_errors` attribute to something appropriate for Postgres.
    """
    reconnect_errors = (
        # Error class, error message fragment (or empty string for all).
        (OperationalError, '2006'),  # MySQL server has gone away.
        (OperationalError, '2013'),  # Lost connection to MySQL server.
        (OperationalError, '2014'),  # Commands out of sync.
        (OperationalError, '4031'),  # Client interaction timeout.

        # mysql-connector raises a slightly different error when an idle
        # connection is terminated by the server. This is equivalent to 2013.
        (OperationalError, 'MySQL Connection not available.'),

        # Postgres error examples:
        #(OperationalError, 'terminat'),
        #(InterfaceError, 'connection already closed'),
    )

    def __init__(self, *args, **kwargs):
        super(ReconnectMixin, self).__init__(*args, **kwargs)

        # Normalize the reconnect errors to a more efficient data-structure.
        self._reconnect_errors = {}
        for exc_class, err_fragment in self.reconnect_errors:
            self._reconnect_errors.setdefault(exc_class, [])
            self._reconnect_errors[exc_class].append(err_fragment.lower())

    def execute_sql(self, sql, params=None, commit=None):
        if commit is not None:
            __deprecated__('"commit" has been deprecated and is a no-op.')
        return self._reconnect(super(ReconnectMixin, self).execute_sql, sql, params)

    def begin(self):
        return self._reconnect(super(ReconnectMixin, self).begin)

    def _reconnect(self, func, *args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as exc:
            # If we are in a transaction, do not reconnect silently as
            # any changes could be lost.
            if self.in_transaction():
                raise exc

            exc_class = type(exc)
            if exc_class not in self._reconnect_errors:
                raise exc

            exc_repr = str(exc).lower()
            for err_fragment in self._reconnect_errors[exc_class]:
                if err_fragment in exc_repr:
                    break
            else:
                raise exc

            if not self.is_closed():
                self.close()
                self.connect()

            return func(*args, **kwargs)
```
