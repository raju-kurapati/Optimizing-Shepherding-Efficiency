# from pyNetLogo tutorials
# Copyright (c) 2010-2018, Delft University of Technology All rights reserved.

import itertools
from math import pi
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns


sns.set_style("white")
sns.set_context("talk")


def normalize(x, xmin, xmax):
    return (x - xmin) / (xmax - xmin)


def plot_circles(ax, locs, names, max_s, stats, smax, smin, fc, ec, lw, zorder):
    s = np.asarray([stats[name] for name in names])
    s = 0.01 + max_s * np.sqrt(normalize(s, smin, smax))

    fill = True
    for loc, name, si in zip(locs, names, s):
        if fc == "w":
            fill = False
        else:
            ec = "none"

        x = np.cos(loc)
        y = np.sin(loc)

        circle = plt.Circle(
            (x, y),
            radius=si,
            ec=ec,
            fc=fc,
            transform=ax.transData._b,
            zorder=zorder,
            lw=lw,
            fill=True,
        )
        ax.add_artist(circle)


def filter_sobol(sobol_indices, names, locs, criterion, threshold):
    if criterion in ["ST", "S1", "S2"]:
        data = sobol_indices[criterion]
        data = np.abs(data)
        data = data.flatten()  # flatten in case of S2
        # TODO:: remove nans

        filtered = [
            (name, locs[i]) for i, name in enumerate(names) if data[i] > threshold
        ]
        filtered_names, filtered_locs = zip(*filtered)
    elif criterion in ["ST_conf", "S1_conf", "S2_conf"]:
        raise NotImplementedError
    else:
        raise ValueError("unknown value for criterion")

    return filtered_names, filtered_locs


def plot_sobol_indices(problem, sobol_indices, criterion="ST", threshold=0.01):
    """plot sobol indices on a radial plot

    Parameters
    ----------
    sobol_indices : dict
                    the return from SAlib
    criterion : {'ST', 'S1', 'S2', 'ST_conf', 'S1_conf', 'S2_conf'}, optional
    threshold : float
                only visualize variables with criterion larger than cutoff

    """
    max_linewidth_s2 = 15  # 25*1.8
    max_s_radius = 0.3

    # prepare data
    # use the absolute values of all the indices
    # sobol_indices = {key:np.abs(stats) for key, stats in sobol_indices.items()}

    # dataframe with ST and S1
    sobol_stats = {key: sobol_indices[key] for key in ["ST", "S1"]}
    sobol_stats = pd.DataFrame(sobol_stats, index=problem["names"])

    smax = sobol_stats.max().max()
    smin = sobol_stats.min().min()

    # dataframe with s2
    s2 = pd.DataFrame(
        sobol_indices["S2"], index=problem["names"], columns=problem["names"]
    )
    s2[s2 < 0.0] = 0.0  # Set negative values to 0 (artifact from small sample sizes)
    s2max = s2.max().max()
    s2min = s2.min().min()

    names = problem["names"]
    n = len(names)
    ticklocs = np.linspace(0, 2 * pi, n + 1)
    locs = ticklocs[0:-1]

    filtered_names, filtered_locs = filter_sobol(
        sobol_indices, names, locs, criterion, threshold
    )

    # setup figure
    fig = plt.figure()
    ax = fig.add_subplot(111, polar=True)
    ax.grid(False)
    ax.spines["polar"].set_visible(False)

    ax.set_xticks(locs)
    ax.set_xticklabels(names)

    ax.set_yticklabels([])
    legend(ax)

    # plot ST
    plot_circles(
        ax,
        filtered_locs,
        filtered_names,
        max_s_radius,
        sobol_stats["ST"],
        smax,
        smin,
        "w",
        "k",
        1,
        9,
    )

    # plot S1
    plot_circles(
        ax,
        filtered_locs,
        filtered_names,
        max_s_radius,
        sobol_stats["S1"],
        smax,
        smin,
        "k",
        "k",
        1,
        10,
    )

    # plot S2
    for name1, name2 in itertools.combinations(zip(filtered_names, filtered_locs), 2):
        name1, loc1 = name1
        name2, loc2 = name2

        weight = s2.loc[name1, name2]
        lw = 0.5 + max_linewidth_s2 * normalize(weight, s2min, s2max)
        ax.plot([loc1, loc2], [1, 1], c="darkgray", lw=lw, zorder=1)

    return fig


from matplotlib.legend_handler import HandlerPatch


class HandlerCircle(HandlerPatch):
    def create_artists(
        self, legend, orig_handle, xdescent, ydescent, width, height, fontsize, trans
    ):
        center = 0.5 * width - 0.5 * xdescent, 0.5 * height - 0.5 * ydescent
        p = plt.Circle(xy=center, radius=orig_handle.radius)
        self.update_prop(p, orig_handle, legend)
        p.set_transform(trans)
        return [p]


def legend(ax):
    some_identifiers = [
        plt.Circle((0, 0), radius=5, color="k", fill=False, lw=1),
        plt.Circle((0, 0), radius=5, color="k", fill=True),
        plt.Line2D([0, 0.5], [0, 0.5], lw=8, color="darkgray"),
    ]
    ax.legend(
        some_identifiers,
        ["ST", "S1", "S2"],
        loc="right",
        borderaxespad=0.1,
        mode="expand",
        handler_map={plt.Circle: HandlerCircle()},
    )


def dict_product_set(**named_arrays):
    """generate a set of dicts from a set of arrays

    Parameters
    ----------
    named_arrays : dict
                   a dict of named arrays

    Returns
    -------
    set
        a set of dicts

    """
    names = list(named_arrays.keys())
    arrays = list(named_arrays.values())

    return iter(dict(zip(names, prod)) for prod in itertools.product(*arrays))


def apply_args_and_kwargs(fn, args, kwargs):
    return fn(*args, **kwargs)


def starstarmap(pool, fn, args_iter, kwargs_iter, **pool_kwargs):
    args_for_starmap = zip(itertools.repeat(fn), args_iter, kwargs_iter)
    return pool.starmap(apply_args_and_kwargs, args_for_starmap, **pool_kwargs)


def py2nl(name):
    """convert a python name to a NL name

    Parameters
    ----------
    name : str
           the python name

    Returns
    -------
    str
        the NL name

    """
    return name.replace("_", "-")


def nl2py(name):
    """convert a NL name to a python name

    Parameters
    ----------
    name : str
           the NL name

    Returns
    -------
    str
        the python name

    """
    return name.replace("-", "_")
