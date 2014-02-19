"""
Fast snippets for sparse matrices.
"""

cimport cython
cimport cpython.list
cimport cpython.int
cimport cpython
cimport numpy as cnp
import numpy as np


ctypedef fused idx_t:
    cnp.int32_t
    cnp.int64_t


ctypedef fused value_t:
    cnp.npy_bool
    cnp.npy_int8
    cnp.npy_uint8
    cnp.npy_int16
    cnp.npy_uint16
    cnp.npy_int32
    cnp.npy_uint32
    cnp.npy_int64
    cnp.npy_uint64
    cnp.npy_float32
    cnp.npy_float64
    float complex
    double complex


def prepare_index_arrays(cnp.ndarray i, cnp.ndarray j, cnp.ndarray x=None):
    """
    Convert index and data arrays to form suitable for passing to the
    Cython fancy getset routines.

    Parameters
    ----------
    i, j
        Index arrays
    x : optional
        Data arrays

    Returns
    -------
    i, j, x
        Re-formatted arrays (x is omitted, if input was None)

    """

    if not i.flags.writeable or not i.dtype in (np.int32, np.int64):
        i = i.astype(np.intp)
    if not j.flags.writeable or not j.dtype in (np.int32, np.int64):
        j = j.astype(np.intp)
    if x is not None:
        if not x.flags.writeable:
            x = x.copy()
        return i, j, x
    else:
        return i, j


cpdef lil_get1(cnp.npy_intp M, cnp.npy_intp N, object[:] rows, object[:] datas,
               cnp.npy_intp i, cnp.npy_intp j):
    """
    Get a single item from LIL matrix.

    Doesn't do output type conversion. Checks for bounds errors.

    Parameters
    ----------
    M, N, rows, datas
        Shape and data arrays for a LIL matrix
    i, j : int
        Indices at which to get

    Returns
    -------
    x
        Value at indices.

    """
    cdef list row, data

    if i < 0:
        i += M
    if i < 0 or i >= M:
        raise IndexError('row index out of bounds')

    if j < 0:
        j += N
    if j < 0 or j >= N:
        raise IndexError('column index out of bounds')

    row = rows[i]
    data = datas[i]
    pos = bisect_left(row, j)

    if pos != len(data) and row[pos] == j:
        return data[pos]
    else:
        return 0


cpdef lil_insert(cnp.npy_intp M, cnp.npy_intp N, object[:] rows, object[:] datas,
                 cnp.npy_intp i, cnp.npy_intp j, value_t x):
    """
    Insert a single item to LIL matrix.

    Checks for bounds errors and deletes item if x is zero.

    Parameters
    ----------
    M, N, rows, datas
        Shape and data arrays for a LIL matrix
    i, j : int
        Indices at which to get
    x
        Value to insert.

    """
    cdef list row, data
    cdef int is_zero

    if i < 0:
        i += M
    if i < 0 or i >= M:
        raise IndexError('row index out of bounds')

    if j < 0:
        j += N
    if j < 0 or j >= N:
        raise IndexError('column index out of bounds')

    row = rows[i]
    data = datas[i]

    if x == 0:
        lil_deleteat_nocheck(rows[i], datas[i], j)
    else:
        lil_insertat_nocheck(rows[i], datas[i], j, x)


def lil_fancy_get(cnp.npy_intp M, cnp.npy_intp N,
                  object[:] rows,
                  object[:] data,
                  object[:] new_rows,
                  object[:] new_data,
                  idx_t[:,:] i_idx,
                  idx_t[:,:] j_idx):
    """
    Get multiple items at given indices in LIL matrix and store to
    another LIL.

    Parameters
    ----------
    M, N, rows, data
        LIL matrix data
    new_rows, new_idx
        Data for LIL matrix to insert to.
        Must be preallocated to shape `i_idx.shape`!
    i_idx, j_idx
        Indices of elements to insert to the new LIL matrix.

    """
    cdef cnp.npy_intp x, y
    cdef idx_t i, j
    cdef object value

    for x in range(i_idx.shape[0]):
        for y in range(i_idx.shape[1]):
            i = i_idx[x,y]
            j = j_idx[x,y]

            value = lil_get1(M, N, rows, data, i, j)

            if value is 0:
                # Object identity as shortcut
                continue

            lil_insertat_nocheck(new_rows[x], new_data[x],
                                 y, value)


def lil_fancy_set(cnp.npy_intp M, cnp.npy_intp N,
                  object[:] rows,
                  object[:] data,
                  idx_t[:,:] i_idx,
                  idx_t[:,:] j_idx,
                  value_t[:,:] values):
    """
    Set multiple items to a LIL matrix.

    Checks for zero elements and deletes them.

    Parameters
    ----------
    M, N, rows, data
        LIL matrix data
    i_idx, j_idx
        Indices of elements to insert to the new LIL matrix.
    values
        Values of items to set.

    """
    cdef cnp.npy_intp x, y
    cdef idx_t i, j

    for x in range(i_idx.shape[0]):
        for y in range(i_idx.shape[1]):
            i = i_idx[x,y]
            j = j_idx[x,y]
            lil_insert[value_t](M, N, rows, data, i, j, values[x, y])


cdef lil_insertat_nocheck(list row, list data, cnp.npy_intp j, object x):
    """
    Insert a single item to LIL matrix.

    Doesn't check for bounds errors. Doesn't check for zero x.

    Parameters
    ----------
    M, N, rows, datas
        Shape and data arrays for a LIL matrix
    i, j : int
        Indices at which to get
    x
        Value to insert.

    """
    cdef cnp.npy_intp pos

    pos = bisect_left(row, j)
    if pos == len(row):
        row.append(j)
        data.append(x)
    elif row[pos] != j:
        row.insert(pos, j)
        data.insert(pos, x)
    else:
        data[pos] = x


cdef lil_deleteat_nocheck(list row, list data, cnp.npy_intp j):
    """
    Delete a single item from a row in LIL matrix.

    Doesn't check for bounds errors.

    Parameters
    ----------
    row, data
        Row data for LIL matrix.
    j : int
        Column index to delete at

    """
    cdef cnp.npy_intp pos
    pos = bisect_left(row, j)
    if pos < len(row) and row[pos] == j:
        del row[pos]
        del data[pos]


@cython.cdivision(True)
@cython.boundscheck(False)
@cython.wraparound(False)
cdef bisect_left(list a, cnp.npy_intp x):
    """
    Bisection search in a sorted list.

    List is assumed to contain objects castable to integers.

    Parameters
    ----------
    a
        List to search in
    x
        Value to search for

    Returns
    -------
    j : int
        Index at value (if present), or at the point to which
        it can be inserted maintaining order.

    """
    cdef cnp.npy_intp hi = len(a)
    cdef cnp.npy_intp lo = 0
    cdef cnp.npy_intp mid, v

    while lo < hi:
        mid = (lo + hi)//2
        v = a[mid]
        if v < x:
            lo = mid + 1
        else:
            hi = mid
    return lo
