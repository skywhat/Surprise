"""
The :mod:`similarities` module includes tools to compute similarity metrics
between users or items. Please refer to the :ref:`notation standards
<notation_standards>`.
"""

cimport numpy as np
import numpy as np

# OK so I changed some stuff: itertool.combinations is not used anymore, it caused a
# weird bug in the mean_diff calculation. I'm pretty sure it used to work OK
# before because we were only testing ml-100k on the 'official' 5-fold cross
# validation sets, where all user ids where ordered. Now that ids can appear in
# any order (because we do our own CV folds), combinations can't be used
# anymore.
# We now do it the 'bruteforce' way, which forces us to have a plain n_x x n_x
# matrix (using combinations we could have (but did not) used  symetric matrix
# structure).
# We definitely need a proper test campaign.

def cosine(n_x, yr):
    """Compute the cosine similarity between all pairs of xs.

    Only *common* users (or items) are taken into account:

    :math:`\\text{cos_sim}(x, x') = \\frac{
    \\sum\\limits_{y \in Y_{xx'}} r_{xy} \cdot r_{x'y}}
    {\\sqrt{\\sum\\limits_{y \in Y_{xx'}} r_{xy}^2} \cdot
    \\sqrt{\\sum\\limits_{y \in Y_{xx'}} r_{x'y}^2}
    }`

    See details on `Wikipedia
    <https://en.wikipedia.org/wiki/Cosine_similarity#Definition>`_.
    """

    # sum (r_xy * r_x'y) for common ys
    cdef np.ndarray[np.int_t, ndim = 2] prods     = np.zeros((n_x, n_x), np.int)
    # number of common ys
    cdef np.ndarray[np.int_t, ndim = 2] freq      = np.zeros((n_x, n_x), np.int)
    # sum (r_xy ^ 2) for common ys
    cdef np.ndarray[np.int_t, ndim = 2] sqi       = np.zeros((n_x, n_x), np.int)
    # sum (r_x'y ^ 2) for common ys
    cdef np.ndarray[np.int_t, ndim = 2] sqj       = np.zeros((n_x, n_x), np.int)
    # the similarity matrix
    cdef np.ndarray[np.double_t, ndim = 2] sim = np.zeros((n_x, n_x))

    # these variables need to be cdef'd so that array lookup can be fast
    cdef int xi = 0
    cdef int xj = 0
    cdef int r1 = 0
    cdef int r2 = 0

    for y, y_ratings in yr.items():
        for xi, r1 in y_ratings:
            for xj, r2 in y_ratings:
                freq[xi, xj] += 1
                prods[xi, xj] += r1 * r2
                sqi[xi, xj] += r1**2
                sqj[xi, xj] += r2**2

    for xi in range(n_x):
        sim[xi, xi] = 1
        for xj in range(xi + 1, n_x):
            if freq[xi, xj] == 0:
                sim[xi, xj] = 0
            else:
                denum = np.sqrt(sqi[xi, xj] * sqj[xi, xj])
                sim[xi, xj] = prods[xi, xj] / denum

            sim[xj, xi] = sim[xi, xj]

    return sim

def msd(n_x, yr):
    """Compute the mean squared difference similarity between all pairs of
    xs.

    Only *common* users (or items) are taken into account:

    :math:`\\text{msd}(x, x') = \\frac{1}{|Y_{xx'}|} \cdot
    \\sum\\limits_{y \in Y_{xx'}} (r_{xy} - r_{x'y})^2`

    :math:`\\text{msd_sim}(x, x') = \\left\\{
    \\begin{array}{ll}
    \\frac{1}{\\text{msd}(x, x')} & \mbox{if }\\text{msd}(x, x') \\neq 0 \\\\
    |Y_{xx'}|& \mbox{else (which is quite arbitrary).}
    \end{array}
    \\right.`

    For details, see third definition on `Wikipedia
    <https://en.wikipedia.org/wiki/Root-mean-square_deviation#Formula>`_.

    """

    # sum (r_xy - r_x'y)**2 for common ys
    cdef np.ndarray[np.double_t, ndim = 2] sq_diff = np.zeros((n_x, n_x), np.double)
    # number of common ys
    cdef np.ndarray[np.int_t,    ndim = 2] freq   = np.zeros((n_x, n_x), np.int)
    # the similarity matrix
    cdef np.ndarray[np.double_t, ndim = 2] sim = np.zeros((n_x, n_x))

    # these variables need to be cdef'd so that array lookup can be fast
    cdef int xi = 0
    cdef int xj = 0
    cdef int r1 = 0
    cdef int r2 = 0

    for y, y_ratings in yr.items():
        for xi, r1 in y_ratings:
            for xj, r2 in y_ratings:
                sq_diff[xi, xj] += (r1 - r2)**2
                freq[xi, xj] += 1

    for xi in range(n_x):
        sim[xi, xi] = 100 # completely arbitrary and useless anyway
        for xj in range(xi + 1, n_x):
            if sq_diff[xi, xj] == 0: # return number of common ys (arbitrary)
                sim[xi, xj] = freq[xi, xj]
            else:  # return inverse of MSD
                sim[xi, xj] = freq[xi, xj] / sq_diff[xi, xj]

            sim[xj, xi] = sim[xi, xj]

    return sim

def compute_mean_diff(n_x, yr):
    """Compute mean_diff, where
    mean_diff[x, x'] = mean(r_xy - r_x'y) for common ys
    """

    # sum (r_xy - r_x'y - mean_diff(r_x - r_x')) for common ys
    cdef np.ndarray[np.double_t, ndim = 2] diff = np.zeros((n_x, n_x), np.double)
    # number of common ys
    cdef np.ndarray[np.int_t,    ndim = 2] freq   = np.zeros((n_x, n_x), np.int)
    # the mean_diff matrix
    cdef np.ndarray[np.double_t, ndim = 2] mean_diff = np.zeros((n_x, n_x))

    # these variables need to be cdef'd so that array lookup can be fast
    cdef int xi = 0
    cdef int xj = 0
    cdef int r1 = 0
    cdef int r2 = 0

    for y, y_ratings in yr.items():
        for xi, r1 in y_ratings:
            for xj, r2 in y_ratings:
                diff[xi, xj] += (r1 - r2)
                freq[xi, xj] += 1

    for xi in range(n_x):
        mean_diff[xi, xi] = 0
        for xj in range(xi + 1, n_x):
            if freq[xi, xj]:
                mean_diff[xi, xj] = diff[xi, xj] / freq[xi, xj]
                mean_diff[xj, xi] = -mean_diff[xi, xj]

    return mean_diff

def msdClone(n_x, yr):
    """compute the 'clone' mean squared difference similarity between all
    pairs of xs. Some properties as for MSDSim apply."""

    # sum (r_xy - r_x'y - mean_diff(x, x')) for common ys
    cdef np.ndarray[np.double_t, ndim = 2] diff = np.zeros((n_x, n_x), np.double)
    # sum (r_xy - r_x'y)**2 for common ys
    cdef np.ndarray[np.double_t, ndim = 2] sq_diff = np.zeros((n_x, n_x), np.double)
    # number of common ys
    cdef np.ndarray[np.int_t,    ndim = 2] freq   = np.zeros((n_x, n_x), np.int)
    # the similarity matrix
    cdef np.ndarray[np.double_t, ndim = 2] sim = np.zeros((n_x, n_x))
    # the matrix of mean differences
    cdef np.ndarray[np.double_t, ndim = 2] mean_diff = compute_mean_diff(n_x, yr)

    # these variables need to be cdef'd so that array lookup can be fast
    cdef int xi = 0
    cdef int xj = 0
    cdef int r1 = 0
    cdef int r2 = 0

    for y, y_ratings in yr.items():
        for xi, r1 in y_ratings:
            for xj, r2 in y_ratings:
                sq_diff[xi, xj] += (r1 - r2 - mean_diff[xi, xj])**2
                freq[xi, xj] += 1

    for xi in range(n_x):
        sim[xi, xi] = 100 # completely arbitrary and useless anyway
        for xj in range(xi + 1, n_x):
            if sq_diff[xi, xj] == 0: # return number of common ys (arbitrary)
                sim[xi, xj] = freq[xi, xj]
            else:  # return inverse of MSD
                sim[xi, xj] = freq[xi, xj] / sq_diff[xi, xj]

            sim[xj, xi] = sim[xi, xj]

    return sim


def pearson(n_x, yr):
    """compute the pearson corr coeff between all pairs of xs.

    Only *common* users (or items) are taken into account:

    :math:`\\text{pearson_sim}(x, x') = \\frac{
    \\sum\\limits_{y \in Y_{xx'}} (r_{xy} -  \mu_x) \cdot (r_{x'y} - \mu_{x'})}
    {\\sqrt{\\sum\\limits_{y \in Y_{xx'}} (r_{xy} -  \mu_x)^2} \cdot
    \\sqrt{\\sum\\limits_{y \in Y_{xx'}} (r_{x'y} -  \mu_{x'})^2}
    }`

    See details on `Wikipedia
    <https://en.wikipedia.org/wiki/Pearson_product-moment_correlation_coefficient#For_a_sample>`_.
    """

    # number of common ys
    cdef np.ndarray[np.int_t,    ndim = 2] freq   = np.zeros((n_x, n_x), np.int)
    # sum (r_xy * r_x'y) for common ys
    cdef np.ndarray[np.int_t,    ndim = 2] prods = np.zeros((n_x, n_x), np.int)
    # sum (rxy ^ 2) for common ys
    cdef np.ndarray[np.int_t,    ndim = 2] sqi = np.zeros((n_x, n_x), np.int)
    # sum (rx'y ^ 2) for common ys
    cdef np.ndarray[np.int_t,    ndim = 2] sqj = np.zeros((n_x, n_x), np.int)
    # sum (rxy) for common ys
    cdef np.ndarray[np.int_t,    ndim = 2] si = np.zeros((n_x, n_x), np.int)
    # sum (rx'y) for common ys
    cdef np.ndarray[np.int_t,    ndim = 2] sj = np.zeros((n_x, n_x), np.int)
    # the similarity matrix
    cdef np.ndarray[np.double_t, ndim = 2] sim = np.zeros((n_x, n_x))

    # these variables need to be cdef'd so that array lookup can be fast
    cdef int xi = 0
    cdef int xj = 0
    cdef int r1 = 0
    cdef int r2 = 0

    for y, y_ratings in yr.items():
        for xi, r1 in y_ratings:
            for xj, r2 in y_ratings:
                prods[xi, xj] += r1 * r2
                freq[xi, xj] += 1
                sqi[xi, xj] += r1**2
                sqj[xi, xj] += r2**2
                si[xi, xj] += r1
                sj[xi, xj] += r2

    for xi in range(n_x):
        sim[xi, xi] = 1
        for xj in range(xi + 1, n_x):
            n = freq[xi, xj]
            num = n * prods[xi, xj] - si[xi, xj] * sj[xi, xj]
            denum = np.sqrt((n * sqi[xi, xj] - si[xi, xj]**2) *
                            (n * sqj[xi, xj] - sj[xi, xj]**2))
            if denum == 0:
                sim[xi, xj] = 0
            else:
                sim[xi, xj] = num / denum

            sim[xj, xi] = sim[xi, xj]

    return sim
