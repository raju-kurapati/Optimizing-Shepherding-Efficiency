from pathlib import Path
from os import PathLike
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib as mpl
from mpl_toolkits.axes_grid1 import make_axes_locatable
import numpy as np


def colorbar(mappable):
    ax = mappable.axes
    fig = ax.figure
    divider = make_axes_locatable(ax)
    cax = divider.append_axes("right", size="5%", pad=0.05)
    return fig.colorbar(mappable, cax=cax)


def plot_parameter_sweep(results_file: PathLike):
    """plot the results of the parameter sweep"""
    from pickle import loads

    _, _, results = loads(Path(results_file).read_bytes())
    # (parameters, _), results, _ = loads(Path(results_file).read_bytes())

    plt.rcParams.update({"text.usetex": True, "font.family": "Computer Modern Roman"})

    # full_df = pd.DataFrame.join(experiments, results)
    success_rate = (
        results.groupby(["num_sheep", "num_neighbors"])
        .mean()["Win?"]
        .unstack(level=0, fill_value=0)
    )
    print(success_rate.head(32))
    fig, ax = plt.subplots(figsize=(5.5, 3))
    cmap = mpl.colors.LinearSegmentedColormap.from_list(
        "blue", ["#1484C3", "#FFFFFF"], N=256
    )
    plot = ax.pcolormesh(
        success_rate.columns,
        success_rate.index,
        success_rate.values,
        cmap=cmap,
    )
    colorbar(plot)
    ax.plot(success_rate.columns, 0.53 * success_rate.columns, "k", linewidth=1)
    ax.plot(success_rate.columns, 3 * np.log(success_rate.columns), "k", linewidth=1)
    # ax.set_xlim(parameters[0].bounds)
    ax.set_xlabel("no. sheep ($N$)")
    # ax.set_ylim(parameters[1].bounds)
    ax.set_ylabel("no. neighbors ($n$)")
    # ax.set_title("Success rate of the Strombom shepherd model")
    ax.set_aspect("equal")

    fig.tight_layout()
    fig.savefig("results.png", dpi=300)
    plt.show()
    return fig, ax


if __name__ == "__main__":
    plot_parameter_sweep("results/results.pkl")
