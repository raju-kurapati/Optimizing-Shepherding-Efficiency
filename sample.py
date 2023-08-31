from enum import Enum, auto
import numpy as np
from dataclasses import dataclass, field
import pandas as pd

from utils import *


class Sampler(Enum):
    """Sample type enum."""

    RANDINT = auto()
    RANDFLOAT = auto()
    LINEARINT = auto()
    LINEARFLOAT = auto()


@dataclass
class Parameter:
    """A parameter.

    Attributes
    ----------
    name : str
           the name of the parameter
    values : list

    """

    name: str
    values: list = field(compare=False)

    def __iter__(self):
        return iter(self.values)


@dataclass
class SampledParameter:
    """A sampled parameter.

    Attributes
    ----------
    name : str
        the name of the parameter
    sample_type : SampleType
        the type of sampling
    bounds : tuple
        the bounds of the sampling
    num : int
        the number of samples

    """

    name: str = field(compare=True)
    sample_type: Sampler = field(compare=False)
    bounds: tuple = field(compare=False)
    num: int = field(compare=False)
    seed: int = field(default=None, compare=False)
    values: list = field(init=False, default_factory=list, compare=False)

    def __post_init__(self):
        self.sample(inplace=True)

    def sample(self, inplace=False):
        """sample from the parameter

        Parameters
        ----------
        inplace : bool, optional
            whether to sample in place, by default False

        Returns
        -------
        np.ndarray
            the samples

        """
        rs = np.random.RandomState(self.seed)

        if self.sample_type == Sampler.RANDINT:
            values = rs.randint(self.bounds[0], self.bounds[1], self.num)
        elif self.sample_type == Sampler.RANDFLOAT:
            values = rs.uniform(self.bounds[0], self.bounds[1], self.num)
        elif self.sample_type == Sampler.LINEARINT:
            values = np.linspace(self.bounds[0], self.bounds[1], self.num, dtype=int)
        elif self.sample_type == Sampler.LINEARFLOAT:
            values = np.linspace(self.bounds[0], self.bounds[1], self.num)
        else:
            raise ValueError("unknown sample type")

        if inplace:
            self.values = values
        else:
            return values

    def __iter__(self):
        return iter(self.values)


def sample(parameters, constraints, resample=False, seed=None):
    """sample from a custom problem

    Parameters
    ----------
    parameters : list of Parameter or SampledParameter
        the parameters to sample from
    problem : dict
        a dict with the following keys
        - num_vars : int
        - names : list of str
        - bounds : list of tuples
        - sample_types : list of SampleType
        - num_samples : list of int
        - restrictions : list of None or functions

    Returns
    -------
    np.ndarray
        the samples

    """
    # generate samples for each variable, if requested
    if resample:
        rs = np.random.RandomState(seed)
        for p in parameters:
            if isinstance(p, SampledParameter):
                p.seed = rs.randint(0, np.iinfo(np.uint16).max, dtype=np.uint16)
                p.sample(inplace=True)

    # form the product of all the samples
    samples = dict_product_set(**{nl2py(p.name): p for p in parameters})

    # filter the samples
    samples = filter(lambda x: all(c(x) for c in constraints), samples)

    return pd.DataFrame.from_records(samples)


class Compare:
    def __init__(self, key1, op, key2):
        if isinstance(key1, Parameter) or isinstance(key1, SampledParameter):
            self.key1 = nl2py(key1.name)
        else:
            self.key1 = nl2py(key1)
        if isinstance(key2, Parameter) or isinstance(key2, SampledParameter):
            self.key2 = nl2py(key2.name)
        else:
            self.key2 = nl2py(key2)
        self.op = op

    def __call__(self, x):
        if self.op == "==":
            return x[self.key1] == x[self.key2]
        elif self.op == "!=":
            return x[self.key1] != x[self.key2]
        elif self.op == ">":
            return x[self.key1] > x[self.key2]
        elif self.op == ">=":
            return x[self.key1] >= x[self.key2]
        elif self.op == "<":
            return x[self.key1] < x[self.key2]
        elif self.op == "<=":
            return x[self.key1] <= x[self.key2]
        else:
            raise ValueError("unknown operator")
